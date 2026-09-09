import Foundation
@preconcurrency import AVFAudio
import FluidAudio
import os

/// Parakeet ASR backend — alt fallback to Apple SpeechRecognizer.
///
/// Per night-pass Track B (2026-05-05). Apple Speech remains the
/// runtime default; this actor is only instantiated when the operator
/// flips the Settings toggle (`AppState.asrBackend = .parakeet`) AND a
/// model directory has been provided.
///
/// **RF Ghost compliance:** No networking happens here. The CoreML
/// model bundles are expected to live at a directory the operator
/// supplies (AirDrop into Files, or an explicit one-time download
/// gated behind operator consent in the Settings UI). Once the bundle
/// is on disk, this code never makes a URLSession call.
///
/// **Model:** Parakeet EOU 120M, through FluidAudio 0.14.4. Streaming variant
/// uses end-of-utterance detection so the medic gets natural sentence
/// boundaries without a manual "end of utterance" tap.
///
/// **Ring buffer:** 30s pre-roll mirrors `SpeechRecognizer`. The mic
/// engine starts on `prime()` and the ring buffer accumulates the most
/// recent 30s of float-PCM. On `start()`, the ring is drained into the
/// FluidAudio manager so the medic gets the pre-tap context indexed
/// into the transcript correctly.
///
/// **Lifecycle:**
///   prime()      — engine + tap on; ring buffer fills
///   start(...)   — load models if not loaded, drain ring, attach live
///   stop()       — schedule a 30s tail; manager finishes, emits final
///   unprime()    — engine + tap off
///   stopImmediate() — error path / app backgrounded
actor ParakeetTranscriptStream: TranscriptStream {

    // MARK: - Configuration

    /// 30-second pre-roll ring buffer. Matches `SpeechRecognizer` so
    /// switching backends doesn't change the user-visible behaviour.
    private let leadDuration: TimeInterval = 30.0
    /// 30-second post-tap tail.
    private let tailDuration: TimeInterval = 30.0

    /// Directory containing the Parakeet CoreML models. If set, used
    /// directly. Otherwise the shared local resolver checks bundled/installed
    /// assets. Only explicit ensureModelsLoaded() preparation may download.
    private var modelDirectory: URL?

    /// Provider for the current dynamic gain multiplier (linear, not
    /// dB). Snapshotted on every audio buffer so a Settings slider
    /// change takes effect on the next sample.
    private let gainProvider: @Sendable () -> Float

    /// FluidAudio streaming chunk size. Each value corresponds to a
    /// distinct CoreML model variant on Hugging Face — switching this
    /// will trigger a fresh model download on next `start()`. Stick
    /// with `.ms160` (the original default + only one we've shipped) to
    /// avoid the re-download cost. Larger chunks raise latency between
    /// EOU emissions but improve throughput; the user's "give me longer
    /// chunks" feedback is addressed primarily by `eouDebounceMs`
    /// rather than by switching the chunk-size variant.
    private let chunkSize: StreamingChunkSize

    /// Sustained-silence threshold (ms) before FluidAudio fires its
    /// EOU callback. FluidAudio's stock default is 1280ms; we set 2000
    /// so the medic gets natural sentence boundaries instead of
    /// mid-thought commits. Pairs with `LiveCaptureScreen.silenceDebounce`
    /// (a UI-side debouncer on top of FluidAudio's own EOU). 2026-05-05.
    private let eouDebounceMs: Int

    /// Optional progress callback for the auto-download path.
    private var downloadProgressHandler: (@Sendable (Double) -> Void)?

    // MARK: - Audio engine

    private let engine = AVAudioEngine()
    private weak var levels: AudioLevels?
    private var inputFormat: AVAudioFormat?
    private var isPrimed: Bool = false
    private struct TimedPCM: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let capturedAt: TimeInterval
    }
    private enum CapturedPCM: @unchecked Sendable {
        case audio(TimedPCM)
        case barrier(CheckedContinuation<Void, Never>)
    }
    private var audioContinuation: AsyncStream<CapturedPCM>.Continuation?
    private var audioConsumer: Task<Void, Never>?
    private var tapGeneration = UUID()

    // MARK: - Resampling (hardware-rate -> 16 kHz mono)
    //
    // Parakeet was trained on 16 kHz mono float32. The iPhone mic captures
    // at the hardware-native rate (typically 44.1 or 48 kHz). Without an
    // explicit converter, we'd be feeding FluidAudio (and the AAC encoder)
    // wrong-rate samples — that's what caused the 5% playback speed and
    // the catastrophic capture rate in the YouTube test.

    /// Sample rate the recognizer + AAC encoder expects.
    private static let targetSampleRate: Double = 16_000

    /// Persistent streaming conversion; per-buffer exhaustion is not EOF.
    private var resampleConverter: ParakeetPCMResampler?

    // MARK: - Pre-roll ring buffer (last ~30s of PCM, same shape as SpeechRecognizer)

    private var ringBuffer: [TimedPCM] = []
    private var ringBufferFrames: Int = 0

    // MARK: - Recognition

    /// FluidAudio's streaming manager. Lazily constructed on `start()`.
    private var manager: StreamingEouAsrManager?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isRecognizing: Bool = false
    private var tailDeadline: Date?

    private var processor: ParakeetAudioProcessor?
    private var isStarting = false
    private var isFinishing = false
    private var captureID = UUID()
    private var tailTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?

    // MARK: - Audio file capture

    private var audioFile: AVAudioFile?
    private(set) var lastRecordingURL: URL?

    // MARK: - Periodic stats logger (long-form observability)

    /// Dev-only breadcrumb timer. Every 5 minutes while a session is
    /// primed/recognising, emit `os_proc_available_memory()` and the
    /// current partial-string length to `os_log` so long-form
    /// (30-90 min) sessions can be diagnosed post-hoc without UI
    /// noise. Never user-facing. Per long-form plan L3.1.
    private var statsTimer: DispatchSourceTimer?
    private static let statsLog = OSLog(subsystem: "ai.tccc", category: "parakeet-longform")

    /// Lock-free buffer-arrival counter — written by the audio render thread,
    /// drained by the 1-second heartbeat. Tells us whether AVAudioEngine is
    /// still feeding us audio, independent of whether FluidAudio is processing
    /// it. Per the diagnostics brief: disambiguates "buffers stop arriving"
    /// from "FluidAudio went silent."
    private let bufferCounter = BufferArrivalCounter()

    /// Tick counter for the 1 s heartbeat. Every 60th tick we also emit
    /// thermal state and memory headroom (the "minute mark" sample).
    private var heartbeatTick: Int = 0

    // MARK: - Init

    init(
        levels: AudioLevels?,
        gainProvider: @escaping @Sendable () -> Float = { 1.0 },
        chunkSize: StreamingChunkSize = .ms160,
        eouDebounceMs: Int = 2000
    ) {
        self.levels = levels
        self.gainProvider = gainProvider
        self.chunkSize = chunkSize
        self.eouDebounceMs = eouDebounceMs
    }

    /// Provide the directory containing the Parakeet CoreML model bundle.
    /// Called from the Settings UI after the operator AirDrops or
    /// downloads the model files. Recording otherwise uses the shared local
    /// resolver and refuses missing assets without downloading.
    func setModelDirectory(_ url: URL) {
        self.modelDirectory = url
    }

    /// Subscribe to download progress for the auto-download path.
    /// Called once per progress tick with `fractionCompleted` in 0..1.
    func setDownloadProgressHandler(_ handler: @escaping @Sendable (Double) -> Void) {
        self.downloadProgressHandler = handler
    }

    /// Public model-fetch entry point. Triggers FluidAudio's
    /// auto-download path explicitly so the operator can prefetch
    /// from Settings before the first recording. Idempotent — if the
    /// model is already cached or loaded, it returns immediately.
    func ensureModelsLoaded() async throws {
        if manager != nil {
            DiagnosticsLogger.shared.log("ensureModelsLoaded · already loaded", category: "asr")
            return
        }
        DiagnosticsLogger.shared.log(
            "ensureModelsLoaded · start · chunkSize=\(chunkSize) eouDebounceMs=\(eouDebounceMs) modelDir=\(modelDirectory?.lastPathComponent ?? "nil")",
            category: "asr"
        )
        let mgr = StreamingEouAsrManager(
            chunkSize: chunkSize,
            eouDebounceMs: eouDebounceMs
        )
        if let dir = modelDirectory ?? OfflineModelAssets.parakeetDirectory {
            try await mgr.loadModels(from: dir)
        } else {
            // Forward FluidAudio's DownloadProgress to our simpler
            // Double-fraction handler.
            let outerHandler = self.downloadProgressHandler
            let downloadHandler: DownloadUtils.ProgressHandler = { progress in
                outerHandler?(progress.fractionCompleted)
            }
            try await mgr.loadModels(
                to: nil,
                configuration: nil,
                progressHandler: downloadHandler
            )
        }
        self.manager = mgr
        DiagnosticsLogger.shared.log("ensureModelsLoaded · loadModels returned OK", category: "asr")
    }

    /// Recording paths never call the SDK's download-capable overload.
    private func loadLocalModels() async throws {
        guard manager == nil else { return }
        guard let directory = modelDirectory ?? OfflineModelAssets.parakeetDirectory,
              OfflineModelAssets.parakeetProblems(at: directory).isEmpty else {
            throw TranscriptStreamError.backendUnavailable("Parakeet assets missing or incomplete. Prepare offline models before recording.")
        }
        let local = StreamingEouAsrManager(chunkSize: chunkSize, eouDebounceMs: eouDebounceMs)
        try await local.loadModels(from: directory)
        manager = local
    }

    // MARK: - Authorization

    func authorize() async throws {
        // Same mic-permission flow as SpeechRecognizer; no Speech
        // framework permission needed since we don't use SFSpeechRecognizer.
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            throw TranscriptStreamError.microphoneDenied
        }
    }

    // MARK: - Engine lifecycle

    func prime() async throws {
        try await loadLocalModels()
        guard !isPrimed else { return }
        _ = await DiagnosticsLogger.shared.startSession()
        DiagnosticsLogger.shared.log(
            "prime · thermal=\(Self.thermalLabel()) memMB=\(os_proc_available_memory() / (1024 * 1024))",
            category: "lifecycle"
        )
        try configureSession()

        let inputNode = engine.inputNode

        // iOS Voice Processing IO Unit: AGC + AEC + noise suppression on
        // the input node, applied BEFORE the tap fires. iOS tracks ambient
        // RMS and pushes speech toward ~-16 dBFS with attack/release tuned
        // for voice. The manual gain slider still applies as a trim on
        // top. Must run BEFORE the format read and tap install. See the
        // matching comment in SpeechRecognizer.prime() for full reasoning.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            inputNode.isVoiceProcessingAGCEnabled = true
            DiagnosticsLogger.shared.log("prime · voice processing AGC enabled", category: "lifecycle")
        } catch {
            DiagnosticsLogger.shared.log(
                "prime · voice processing enable failed: \(error.localizedDescription) — falling back to unity-gain capture",
                category: "lifecycle"
            )
        }

        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format
        DiagnosticsLogger.shared.log(
            "prime · inputFormat sampleRate=\(format.sampleRate) ch=\(format.channelCount) target=\(Self.targetSampleRate)",
            category: "lifecycle"
        )

        // Build the hardware -> 16 kHz mono converter. Parakeet expects
        // 16 kHz; the AAC file is also written at 16 kHz; both consume the
        // same converted buffer.
        if let converter = ParakeetPCMResampler(inputFormat: format) {
            self.resampleConverter = converter
            DiagnosticsLogger.shared.log(
                "prime · converter built \(format.sampleRate)Hz ch=\(format.channelCount) -> 16000Hz ch=1",
                category: "lifecycle"
            )
        } else {
            DiagnosticsLogger.shared.log(
                "prime · converter init FAILED — recognition will report incomplete audio",
                category: "lifecycle"
            )
        }

        let weakLevels = self.levels
        let arrivalCounter = self.bufferCounter
        let (audioStream, audioContinuation) = AsyncStream<CapturedPCM>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.audioContinuation = audioContinuation
        let generation = UUID()
        tapGeneration = generation
        audioConsumer = Task { [weak self] in
            for await frame in audioStream {
                guard !Task.isCancelled else { break }
                switch frame {
                case .audio(let captured):
                    await self?.ingestBuffer(captured, generation: generation)
                case .barrier(let completion):
                    await self?.endAudioAdmission(generation: generation)
                    completion.resume()
                }
            }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Date the earliest sample before copying or queueing can delay it.
            let capturedAt = ProcessInfo.processInfo.systemUptime
                - Double(buffer.frameLength) / buffer.format.sampleRate
            let rms = Self.computeRMS(buffer)
            arrivalCounter.record(frames: Int(buffer.frameLength), rms: rms)
            if let weakLevels { Task { @MainActor in weakLevels.ingest(rms) } }
            guard let copy = Self.copyBuffer(buffer) else {
                Task { [weak self] in await self?.audioOverrun(generation: generation) }
                return
            }
            if case .dropped = audioContinuation.yield(.audio(TimedPCM(buffer: copy, capturedAt: capturedAt))) {
                Task { [weak self] in await self?.audioOverrun(generation: generation) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioContinuation.finish()
            audioConsumer?.cancel()
            DiagnosticsLogger.shared.log("prime · engine.start FAILED: \(error.localizedDescription)", category: "lifecycle")
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isPrimed = true
        DiagnosticsLogger.shared.log("prime · engine.start OK", category: "lifecycle")
        startStatsTimer()
    }

    private func resampleToTarget(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = resampleConverter else { return nil }
        do { return try converter.convert(input) }
        catch {
            DiagnosticsLogger.shared.log("audio conversion failed: \(error.localizedDescription)", category: "asr")
            return nil
        }
    }

    nonisolated private static func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    func unprime() async {
        if isStarting { captureID = UUID() } // cancels a start suspended in model loading
        await teardownRecognizer()
        audioContinuation?.finish(); audioContinuation = nil
        audioConsumer?.cancel(); audioConsumer = nil
        tapGeneration = UUID()
        stopStatsTimer()
        guard isPrimed else { return }
        DiagnosticsLogger.shared.log(
            "unprime · thermal=\(Self.thermalLabel()) memMB=\(os_proc_available_memory() / (1024 * 1024)) ticks=\(heartbeatTick)",
            category: "lifecycle"
        )
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        ringBuffer.removeAll()
        ringBufferFrames = 0
        isPrimed = false
        let weakLevels = self.levels
        if let weakLevels {
            Task { @MainActor in weakLevels.reset() }
        }
        await DiagnosticsLogger.shared.endSession()
    }

    // MARK: - Recognition lifecycle

    func start(audioURL: URL? = nil) async throws -> AsyncStream<RecognitionUpdate> {
        guard !isRecognizing, !isStarting, !isFinishing else {
            throw TranscriptStreamError.alreadyRunning
        }
        isStarting = true
        defer { isStarting = false }
        let id = UUID()
        captureID = id
        if !isPrimed { try await prime() }
        try await loadLocalModels()
        guard captureID == id, let manager else {
            throw TranscriptStreamError.backendUnavailable("Capture cancelled during startup")
        }

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        self.tailDeadline = nil
        lastRecordingURL = nil
        var recordingIssue: String?
        if let audioURL {
            do {
                try ProtectedWrite.createEmpty(at: audioURL)
                audioFile = try AVAudioFile(forWriting: audioURL,
                    settings: AudioCaptureConfig.aacOutputSettings,
                    commonFormat: .pcmFormatFloat32, interleaved: false)
                lastRecordingURL = audioURL
            } catch {
                audioFile = nil
                recordingIssue = "Audio recording unavailable: \(error.localizedDescription)"
            }
        }
        let processor = ParakeetAudioProcessor(decoder: FluidParakeetDecoder(manager: manager),
            captureID: id, onUpdate: { update in continuation.yield(update) }, onFinish: {})
        self.processor = processor
        if let recordingIssue {
            continuation.yield(RecognitionUpdate(text: "", isFinal: false, timestamp: Date(),
                captureID: id, issue: recordingIssue, audioUnavailable: true))
        }
        // No suspension between the pre-roll snapshot and live admission.
        // Preserve the audio acquisition time for operator-decision checks.
        for captured in ringBuffer {
            enqueueForRecognition(captured.buffer, capturedAt: captured.capturedAt)
            writeRecording(captured.buffer)
        }
        isRecognizing = true
        startStatsTimer()
        return stream
    }

    func stop() async {
        guard isRecognizing, !isFinishing, tailDeadline == nil else { return }
        tailDeadline = Date().addingTimeInterval(tailDuration)
        let id = captureID
        tailTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await self?.endTail(captureID: id)
        }
    }

    private func endTail(captureID: UUID) async {
        guard self.captureID == captureID else { return }
        await teardownRecognizer()
    }

    func stopImmediate() async {
        if isStarting { captureID = UUID() }
        await teardownRecognizer()
        stopStatsTimer()
    }

    func forceFinalize() async {
        guard isRecognizing, !isFinishing else { return }
        processor?.requestBoundary()
    }

    // MARK: - Stats timer (long-form observability)

    /// 1-second repeating heartbeat. Drains the lock-free buffer-arrival
    /// counter every tick (so we always know if AVAudioEngine is still
    /// feeding us audio), and every 60 ticks samples thermal state +
    /// memory headroom for the long-form / ANE-throttle diagnosis.
    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let stream = self else { return }
            Task { await stream.emitStats() }
        }
        timer.resume()
        statsTimer = timer
    }

    /// Cancel the stats timer if running. Idempotent.
    private func stopStatsTimer() {
        statsTimer?.cancel()
        statsTimer = nil
    }

    /// Single 1 s heartbeat tick. Always emits buffer-arrival stats from
    /// the last second. Every 60th tick (≈ once a minute) also emits
    /// thermal state + memory headroom.
    private func emitStats() {
        heartbeatTick += 1
        let snap = bufferCounter.drain()
        DiagnosticsLogger.shared.log(
            "buf · sec=\(heartbeatTick) bufs=\(snap.count) frames=\(snap.totalFrames) lastRMS=\(String(format: "%.4f", snap.lastRMS))",
            category: "buffer"
        )
        if heartbeatTick % 60 == 0 {
            let availableBytes = os_proc_available_memory()
            let availableMB = availableBytes / (1024 * 1024)
            DiagnosticsLogger.shared.log(
                "minute · thermal=\(Self.thermalLabel()) memMB=\(availableMB) isRecognizing=\(isRecognizing)",
                category: "minute"
            )
            os_log(
                "longform stats: available_mem=%lldMB isRecognizing=%{bool}d",
                log: Self.statsLog,
                type: .default,
                availableMB,
                isRecognizing
            )
        }
    }

    // MARK: - Tap-callback path

    private func ingestBuffer(_ captured: TimedPCM, generation: UUID) {
        guard generation == tapGeneration else { return }
        guard let working = resampleToTarget(captured.buffer) else {
            processor?.fail("Audio conversion failed; transcription is incomplete")
            return
        }
        // A converter can legitimately buffer its initial input before emitting PCM.
        guard working.frameLength > 0 else { return }

        // Apply variable dynamic gain BEFORE storing/streaming so the
        // ring buffer, level meter, and ASR all see the post-gain
        // signal. The gainProvider closure reads the current Settings
        // slider value on every tick.
        let gain = gainProvider()
        if gain != 1.0 {
            Self.applyGain(working, gain: gain)
        }

        // Always: maintain the ring buffer (now in target format).
        ringBuffer.append(TimedPCM(buffer: working, capturedAt: captured.capturedAt))
        ringBufferFrames += Int(working.frameLength)
        let sampleRate = working.format.sampleRate
        let maxFrames = Int(leadDuration * sampleRate)
        while ringBufferFrames > maxFrames, !ringBuffer.isEmpty {
            let oldest = ringBuffer.removeFirst()
            ringBufferFrames -= Int(oldest.buffer.frameLength)
        }

        guard isRecognizing else { return }

        enqueueForRecognition(working, capturedAt: captured.capturedAt)
        writeRecording(working)
    }

    private func audioOverrun(generation: UUID) {
        guard generation == tapGeneration else { return }
        processor?.fail("Audio input queue overrun; transcription is incomplete")
        if isRecognizing {
            continuation?.yield(RecognitionUpdate(text: "", isFinal: false, timestamp: Date(),
                captureID: captureID, issue: "Audio input queue overrun; recording may have gaps"))
        }
    }

    private func enqueueForRecognition(_ buffer: AVAudioPCMBuffer, capturedAt: TimeInterval) {
        guard buffer.format.sampleRate == Self.targetSampleRate,
              buffer.format.channelCount == 1, let data = buffer.floatChannelData else {
            processor?.fail("Unsupported audio format; transcription is incomplete")
            return
        }
        let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        _ = processor?.enqueue(samples, capturedAt: capturedAt)
    }

    private func writeRecording(_ buffer: AVAudioPCMBuffer) {
        do { try audioFile?.write(from: buffer) }
        catch {
            audioFile = nil
            lastRecordingURL = nil
            continuation?.yield(RecognitionUpdate(text: "", isFinal: false, timestamp: Date(),
                captureID: captureID, issue: "Audio recording failed: \(error.localizedDescription)",
                audioUnavailable: true))
        }
    }

    /// In-place sample-level gain. Float buffers (the iOS engine's
    /// default format) get a multiply pass; Int16 buffers (uncommon
    /// in our pipeline) are saturated to ±32767 to avoid wrap.
    private static func applyGain(_ buffer: AVAudioPCMBuffer, gain: Float) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let data = buffer.floatChannelData {
            for ch in 0..<channels {
                let p = data[ch]
                for i in 0..<frames {
                    p[i] *= gain
                }
            }
        } else if let data = buffer.int16ChannelData {
            for ch in 0..<channels {
                let p = data[ch]
                for i in 0..<frames {
                    let scaled = Float(p[i]) * gain
                    p[i] = Int16(max(-32767, min(32767, scaled)))
                }
            }
        }
    }

    // MARK: - Teardown

    private func endAudioAdmission(generation: UUID) {
        guard generation == tapGeneration else { return }
        isRecognizing = false
    }

    /// The marker follows every microphone buffer accepted before the cutoff.
    /// Retrying a full queue preserves the control marker without dropping audio.
    private func drainAudioIngress() async {
        guard let audioContinuation else {
            isRecognizing = false
            return
        }
        await withCheckedContinuation { completion in
            Task {
                while true {
                    switch audioContinuation.yield(.barrier(completion)) {
                    case .enqueued:
                        return
                    case .dropped:
                        await Task.yield()
                    case .terminated:
                        isRecognizing = false
                        processor?.fail("Audio input ended before capture could drain")
                        completion.resume()
                        return
                    @unknown default:
                        isRecognizing = false
                        processor?.fail("Audio input could not complete its capture boundary")
                        completion.resume()
                        return
                    }
                }
            }
        }
    }

    private func teardownRecognizer() async {
        if let teardownTask { await teardownTask.value; return }
        guard isRecognizing else { return }
        isFinishing = true
        tailDeadline = nil
        tailTask?.cancel(); tailTask = nil
        let processor = self.processor
        let task = Task<Void, Never> {
            await drainAudioIngress()
            if let processor { await processor.closeAndDrain() }
            self.processor = nil
            audioFile = nil
            if let url = lastRecordingURL { try? ProtectedWrite.markProtected(at: url) }
            continuation?.finish()
            continuation = nil
            teardownTask = nil
            isFinishing = false
            stopStatsTimer()
        }
        teardownTask = task
        await task.value
    }

    // MARK: - Helpers

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func copyBuffer(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameCapacity) else {
            return nil
        }
        copy.frameLength = b.frameLength
        let frames = Int(b.frameLength)
        let channels = Int(b.format.channelCount)
        if let src = b.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Float>.size)
            }
        } else if let src = b.int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels {
                memcpy(dst[ch], src[ch], frames * MemoryLayout<Int16>.size)
            }
        }
        return copy
    }

    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = samples[i]
            sum += s * s
        }
        return sqrtf(sum / Float(frameLength))
    }
}


/// The serial processor is the sole caller of this driver. Never call the
/// reentrant FluidAudio manager concurrently while inference is suspended.
actor FluidParakeetDecoder: ParakeetDecoding {
    let manager: StreamingEouAsrManager
    init(manager: StreamingEouAsrManager) { self.manager = manager }

    func process(_ samples: [Float]) async throws -> ParakeetDecodeResult {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false),
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)),
            let target = buffer.floatChannelData else {
            throw TranscriptStreamError.backendUnavailable("Cannot allocate decoder audio buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { target[0].update(from: base, count: source.count) }
        }
        _ = try await manager.process(audioBuffer: buffer)
        return await ParakeetDecodeResult(text: manager.getPartialTranscript(),
            endOfUtterance: manager.eouDetected)
    }

    func finish() async throws -> String { try await manager.finish() }
    func reset() async { await manager.reset() }
}
