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
/// **Model:** parakeet-tdt-0.6b-v2 (English-only, CC-BY-4.0 from
/// NVIDIA, repackaged as CoreML by FluidInference). Streaming variant
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
    /// directly. If nil, FluidAudio's auto-download path runs on
    /// first `start()` (one HTTPS fetch from Hugging Face,
    /// progress-callback driven, cached in Application Support
    /// thereafter — RF Ghost is preserved post-download).
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

    // MARK: - Pre-roll ring buffer (last ~30s of PCM, same shape as SpeechRecognizer)

    private var ringBuffer: [AVAudioPCMBuffer] = []
    private var ringBufferFrames: Int = 0

    // MARK: - Recognition

    /// FluidAudio's streaming manager. Lazily constructed on `start()`.
    private var manager: StreamingEouAsrManager?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isRecognizing: Bool = false
    private var tailDeadline: Date?

    /// Latest accumulated transcript — Parakeet emits incremental
    /// partials and EOU-bounded finals. We track both so the
    /// `RecognitionUpdate` stream mirrors what `SpeechRecognizer` would
    /// produce.
    private var currentPartial: String = ""

    /// Defensive upper bound on partial-string length. If the streaming
    /// recognizer fails to emit an EOU final (silence-detection
    /// regression, mic glitch), the accumulating partial would grow
    /// unbounded over a 30-90 min recording. Force-finalize at this
    /// ceiling so memory + UI cost stay bounded.
    private let partialStringCeiling = 2000

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
    /// downloads the model files. If you skip this, FluidAudio's
    /// auto-download path runs on first start().
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
        if manager != nil { return }
        let mgr = StreamingEouAsrManager(
            chunkSize: chunkSize,
            eouDebounceMs: eouDebounceMs
        )
        await mgr.setPartialCallback { [weak self] partial in
            Task { await self?.emitPartial(partial) }
        }
        await mgr.setEouCallback { [weak self] finalText in
            Task { await self?.emitFinal(finalText) }
        }
        if let dir = modelDirectory {
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
        guard !isPrimed else { return }
        try configureSession()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        let weakLevels = self.levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let copy = Self.copyBuffer(buffer) else { return }
            let rms = Self.computeRMS(buffer)
            if let weakLevels {
                Task { @MainActor in weakLevels.ingest(rms) }
            }
            Task { [weak self] in
                await self?.ingestBuffer(copy)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isPrimed = true
        startStatsTimer()
    }

    func unprime() async {
        if isRecognizing { await teardownRecognizer() }
        guard isPrimed else { return }
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
    }

    // MARK: - Recognition lifecycle

    func start(audioURL: URL? = nil) async throws -> AsyncStream<RecognitionUpdate> {
        if !isPrimed {
            try await prime()
        }
        guard !isRecognizing else {
            throw TranscriptStreamError.alreadyRunning
        }

        // Auto-load models if not already loaded. Uses provided
        // modelDirectory if set; otherwise FluidAudio downloads from
        // Hugging Face into Application Support cache.
        try await ensureModelsLoaded()

        // Open audio file for writing if URL provided.
        // Pre-create the file with NSFileProtectionComplete so the streamed
        // AVAudioFile writes inherit Data Protection. CLAUDE.md hard
        // constraint #3 — casualty audio at rest must be AES-256.
        if let audioURL, let format = inputFormat {
            do {
                try ProtectedWrite.createEmpty(at: audioURL)
                // AAC encode-on-write. AVFoundation handles PCM -> AAC internally for
                // .m4a output. If a future iOS release introduces frame-boundary errors
                // at AAC's 1024-sample input boundary vs our 4096-sample tap buffer,
                // fall back to an explicit AVAudioConverter with an inputBlock loop.
                //
                // Settings mirror `AppState.aacOutputSettings` (the canonical
                // source) but are inlined here because that property is
                // @MainActor-isolated and `[String: Any]` is non-Sendable, so
                // it cannot cross the actor boundary into this actor's context.
                let aacSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 32_000,
                ]
                let file = try AVAudioFile(
                    forWriting: audioURL,
                    settings: aacSettings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                self.audioFile = file
                self.lastRecordingURL = audioURL
            } catch {
                self.audioFile = nil
            }
        }

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        self.tailDeadline = nil
        self.isRecognizing = true
        self.currentPartial = ""

        // Drain pre-roll AFTER the continuation is wired so any callbacks that
        // fire during/after drain land somewhere instead of being dropped.
        if let manager {
            for buf in ringBuffer {
                try? await manager.appendAudio(buf)
                try? audioFile?.write(from: buf)
            }
        }

        return stream
    }

    func stop() async {
        guard isRecognizing else { return }
        if tailDeadline == nil {
            tailDeadline = Date().addingTimeInterval(tailDuration)
        }
        stopStatsTimer()
    }

    func stopImmediate() async {
        await teardownRecognizer()
        stopStatsTimer()
    }

    // MARK: - Stats timer (long-form observability)

    /// Schedule a 5-minute repeating timer that emits memory and
    /// partial-string-length breadcrumbs. Idempotent — calling twice
    /// is a no-op while a timer is already live.
    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(300), repeating: .seconds(300))
        timer.setEventHandler { [weak self] in
            Task { await self?.emitStats() }
        }
        timer.resume()
        statsTimer = timer
    }

    /// Cancel the stats timer if running. Idempotent.
    private func stopStatsTimer() {
        statsTimer?.cancel()
        statsTimer = nil
    }

    /// Emit a single breadcrumb. Reads `os_proc_available_memory()`
    /// (bytes of headroom before iOS jetsams the app) and the current
    /// partial-string length. Dev breadcrumb only — `os_log` default
    /// level so it's visible in Console.app under
    /// subsystem `ai.tccc` / category `parakeet-longform`, but not
    /// user-facing.
    private func emitStats() {
        let availableBytes = os_proc_available_memory()
        let availableMB = availableBytes / (1024 * 1024)
        let partialLen = currentPartial.count
        os_log(
            "longform stats: available_mem=%lldMB partial_len=%d isRecognizing=%{bool}d",
            log: Self.statsLog,
            type: .default,
            availableMB,
            partialLen,
            isRecognizing
        )
    }

    // MARK: - Tap-callback path

    private func ingestBuffer(_ buffer: AVAudioPCMBuffer) {
        // Apply variable dynamic gain BEFORE storing/streaming so the
        // ring buffer, level meter, and ASR all see the post-gain
        // signal. The gainProvider closure reads the current Settings
        // slider value on every tick.
        let gain = gainProvider()
        if gain != 1.0 {
            Self.applyGain(buffer, gain: gain)
        }

        // Always: maintain the ring buffer.
        ringBuffer.append(buffer)
        ringBufferFrames += Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        let maxFrames = Int(leadDuration * sampleRate)
        while ringBufferFrames > maxFrames, !ringBuffer.isEmpty {
            let oldest = ringBuffer.removeFirst()
            ringBufferFrames -= Int(oldest.frameLength)
        }

        guard isRecognizing else { return }

        // Append to FluidAudio manager + audio file.
        if let manager {
            Task { try? await manager.appendAudio(buffer) }
        }
        try? audioFile?.write(from: buffer)

        // Tail deadline check.
        if let deadline = tailDeadline, Date() >= deadline {
            Task { await self.teardownRecognizer() }
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

    // MARK: - Emission helpers

    /// Called from FluidAudio's partial-transcript callback. Forwards
    /// the partial text into the AsyncStream so the UI can show it as
    /// "ghost text" before EOU.
    private func emitPartial(_ partial: String) {
        currentPartial = partial
        // Defensive ceiling: if the partial grows beyond
        // `partialStringCeiling` chars without an EOU final, force-finalize
        // it now to avoid unbounded growth over long recordings.
        if partial.count > partialStringCeiling {
            emitFinal(partial)
            currentPartial = ""
            return
        }
        continuation?.yield(
            RecognitionUpdate(text: partial, isFinal: false, timestamp: Date()))
    }

    /// Called from FluidAudio's EOU callback when end-of-utterance is
    /// detected. Emits a final update to the stream and resets the
    /// partial accumulator.
    private func emitFinal(_ finalText: String) {
        continuation?.yield(
            RecognitionUpdate(text: finalText, isFinal: true, timestamp: Date()))
        currentPartial = ""
    }

    // MARK: - Teardown

    private func teardownRecognizer() async {
        guard isRecognizing else { return }
        isRecognizing = false
        tailDeadline = nil

        // Flush any remaining audio + tail through the manager.
        if let manager {
            do {
                let finalText = try await manager.finish()
                if !finalText.isEmpty {
                    emitFinal(finalText)
                }
            } catch {
                // Don't crash on cleanup failures.
            }
        }

        let closedURL = lastRecordingURL
        audioFile = nil
        // Re-mark complete protection after closing the streamed file.
        // Idempotent; createEmpty already set it, but AVAudioFile may have
        // unset/touched attributes during close.
        if let closedURL {
            try? ProtectedWrite.markProtected(at: closedURL)
        }
        continuation?.finish()
        continuation = nil
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
