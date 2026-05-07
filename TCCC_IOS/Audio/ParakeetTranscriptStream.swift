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

    // MARK: - Resampling (hardware-rate -> 16 kHz mono)
    //
    // Parakeet was trained on 16 kHz mono float32. The iPhone mic captures
    // at the hardware-native rate (typically 44.1 or 48 kHz). Without an
    // explicit converter, we'd be feeding FluidAudio (and the AAC encoder)
    // wrong-rate samples — that's what caused the 5% playback speed and
    // the catastrophic capture rate in the YouTube test.

    /// Sample rate the recognizer + AAC encoder expects.
    private static let targetSampleRate: Double = 16_000

    /// 16 kHz mono float32, non-interleaved. Matches Parakeet's input
    /// format and the AAC encode settings.
    private static let targetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: targetSampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Lazy converter from hardware format to `targetFormat`. Created in
    /// `prime()` once we know the actual input format. Reused across all
    /// tap buffers — converter holds no per-buffer state we care about.
    private var resampleConverter: AVAudioConverter?

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
    ///
    /// Raised 2000 -> 8000 after device feedback that fast continuous
    /// speech (a YouTube monologue, no 2 s pauses) was getting truncated
    /// at the ceiling boundary. 8000 chars ≈ 1500 spoken words ≈ 7-8 min
    /// of continuous fast speech — plenty of headroom while still bounded.
    private let partialStringCeiling = 8000

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
        DiagnosticsLogger.shared.log("ensureModelsLoaded · loadModels returned OK", category: "asr")
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
        _ = await DiagnosticsLogger.shared.startSession()
        DiagnosticsLogger.shared.log(
            "prime · thermal=\(Self.thermalLabel()) memMB=\(os_proc_available_memory() / (1024 * 1024))",
            category: "lifecycle"
        )
        try configureSession()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format
        DiagnosticsLogger.shared.log(
            "prime · inputFormat sampleRate=\(format.sampleRate) ch=\(format.channelCount) target=\(Self.targetSampleRate)",
            category: "lifecycle"
        )

        // Build the hardware -> 16 kHz mono converter. Parakeet expects
        // 16 kHz; the AAC file is also written at 16 kHz; both consume the
        // same converted buffer.
        if let converter = AVAudioConverter(from: format, to: Self.targetFormat) {
            self.resampleConverter = converter
            DiagnosticsLogger.shared.log(
                "prime · converter built \(format.sampleRate)Hz ch=\(format.channelCount) -> 16000Hz ch=1",
                category: "lifecycle"
            )
        } else {
            DiagnosticsLogger.shared.log(
                "prime · converter init FAILED — falling back to passthrough (capture quality will degrade)",
                category: "lifecycle"
            )
        }

        let weakLevels = self.levels
        let arrivalCounter = self.bufferCounter
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = Self.computeRMS(buffer)
            // Diagnostics: lock-free counter so the audio render thread
            // never blocks on file I/O or actor isolation.
            arrivalCounter.record(frames: Int(buffer.frameLength), rms: rms)
            if let weakLevels {
                Task { @MainActor in weakLevels.ingest(rms) }
            }
            // Hand the raw buffer (still hardware format) to the actor.
            // Resampling happens inside ingestBuffer so it runs on the
            // actor's queue, not the render thread.
            guard let copy = Self.copyBuffer(buffer) else { return }
            Task { [weak self] in
                await self?.ingestBuffer(copy)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            DiagnosticsLogger.shared.log("prime · engine.start FAILED: \(error.localizedDescription)", category: "lifecycle")
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isPrimed = true
        DiagnosticsLogger.shared.log("prime · engine.start OK", category: "lifecycle")
        startStatsTimer()
    }

    /// Convert a hardware-format PCM buffer to 16 kHz mono float32 using
    /// the prebuilt `resampleConverter`. Returns nil on converter error or
    /// if the converter isn't initialised.
    private func resampleToTarget(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = resampleConverter else { return nil }

        // Output buffer capacity: at most ratio * input frames + a little
        // slack. Going from 48k -> 16k that's frames/3.
        let ratio = Self.targetSampleRate / converter.inputFormat.sampleRate
        let outFrameCapacity = AVAudioFrameCount(
            ceil(Double(input.frameLength) * ratio) + 16
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: outFrameCapacity
        ) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error || conversionError != nil {
            return nil
        }
        return output
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
        if isRecognizing { await teardownRecognizer() }
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
        if !isPrimed {
            try await prime()
        }
        guard !isRecognizing else {
            throw TranscriptStreamError.alreadyRunning
        }
        DiagnosticsLogger.shared.log(
            "start · audioURL=\(audioURL?.lastPathComponent ?? "nil")",
            category: "lifecycle"
        )

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
                let file = try AVAudioFile(
                    forWriting: audioURL,
                    settings: AudioCaptureConfig.aacOutputSettings,
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
        DiagnosticsLogger.shared.log(
            "stop · tail-scheduled · ticks=\(heartbeatTick) partialLen=\(currentPartial.count)",
            category: "lifecycle"
        )
        if tailDeadline == nil {
            tailDeadline = Date().addingTimeInterval(tailDuration)
        }
        stopStatsTimer()
    }

    func stopImmediate() async {
        DiagnosticsLogger.shared.log(
            "stopImmediate · ticks=\(heartbeatTick) partialLen=\(currentPartial.count)",
            category: "lifecycle"
        )
        await teardownRecognizer()
        stopStatsTimer()
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

    /// Single 1 s heartbeat tick. Always emits buffer-arrival stats from
    /// the last second. Every 60th tick (≈ once a minute) also emits
    /// thermal state + memory headroom.
    private func emitStats() {
        heartbeatTick += 1
        let snap = bufferCounter.drain()
        DiagnosticsLogger.shared.log(
            "buf · sec=\(heartbeatTick) bufs=\(snap.count) frames=\(snap.totalFrames) lastRMS=\(String(format: "%.4f", snap.lastRMS)) partialLen=\(currentPartial.count)",
            category: "buffer"
        )
        if heartbeatTick % 60 == 0 {
            let availableBytes = os_proc_available_memory()
            let availableMB = availableBytes / (1024 * 1024)
            DiagnosticsLogger.shared.log(
                "minute · thermal=\(Self.thermalLabel()) memMB=\(availableMB) partialLen=\(currentPartial.count) isRecognizing=\(isRecognizing)",
                category: "minute"
            )
            os_log(
                "longform stats: available_mem=%lldMB partial_len=%d isRecognizing=%{bool}d",
                log: Self.statsLog,
                type: .default,
                availableMB,
                currentPartial.count,
                isRecognizing
            )
        }
    }

    // MARK: - Tap-callback path

    private func ingestBuffer(_ buffer: AVAudioPCMBuffer) {
        // Resample hardware-format buffer (e.g. 48 kHz mono) to 16 kHz
        // mono float32. Both FluidAudio (Parakeet expects 16 kHz) and the
        // AAC encoder consume the resampled buffer. If the converter is
        // unavailable for any reason, fall back to passthrough so we
        // don't silently lose audio entirely — but this case should not
        // happen in practice.
        let working: AVAudioPCMBuffer
        if let resampled = resampleToTarget(buffer) {
            working = resampled
        } else {
            working = buffer
        }

        // Apply variable dynamic gain BEFORE storing/streaming so the
        // ring buffer, level meter, and ASR all see the post-gain
        // signal. The gainProvider closure reads the current Settings
        // slider value on every tick.
        let gain = gainProvider()
        if gain != 1.0 {
            Self.applyGain(working, gain: gain)
        }

        // Always: maintain the ring buffer (now in target format).
        ringBuffer.append(working)
        ringBufferFrames += Int(working.frameLength)
        let sampleRate = working.format.sampleRate
        let maxFrames = Int(leadDuration * sampleRate)
        while ringBufferFrames > maxFrames, !ringBuffer.isEmpty {
            let oldest = ringBuffer.removeFirst()
            ringBufferFrames -= Int(oldest.frameLength)
        }

        guard isRecognizing else { return }

        // Append to FluidAudio manager + audio file. Both expect 16 kHz
        // mono float32 (Parakeet's training rate; AAC settings declare
        // 16 kHz mono).
        if let manager {
            Task { try? await manager.appendAudio(working) }
        }
        try? audioFile?.write(from: working)

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
        DiagnosticsLogger.shared.log(
            "partial · len=\(partial.count) tail=\"\(String(partial.suffix(40)))\"",
            category: "asr"
        )

        // Implicit-EOU detection. If Parakeet's new partial is not a
        // continuation of `currentPartial` (i.e., neither a forward
        // extension nor a small backward revision), treat that as an
        // utterance boundary and commit the prior partial as a final
        // line BEFORE adopting the new one. Without this, fast continuous
        // speech where Parakeet's internal silence threshold never fires
        // EOU produces visible bubble-overwriting: the partial visually
        // replaces itself instead of growing into a new finalised line.
        //
        // Bug report 2026-05-07 documented this as MEDIC 01:40 bubbles
        // wiping their content as new utterances came in. Ground truth
        // showed 4 distinct utterances; only ~1 was being committed.
        let isContinuation = partial.hasPrefix(currentPartial)
        let isShortRevision = currentPartial.hasPrefix(partial)
        let priorIsSubstantial = currentPartial.count > 20
        if !currentPartial.isEmpty,
           !isContinuation,
           !isShortRevision,
           priorIsSubstantial {
            DiagnosticsLogger.shared.log(
                "partial · IMPLICIT-EOU committing prior (len=\(currentPartial.count)) before new utterance",
                category: "asr"
            )
            let priorPartial = currentPartial
            currentPartial = ""
            emitFinal(priorPartial)
        }

        currentPartial = partial
        // Defensive ceiling: if the partial grows beyond
        // `partialStringCeiling` chars without an EOU final, force-finalize
        // it now to avoid unbounded growth over long recordings.
        if partial.count > partialStringCeiling {
            DiagnosticsLogger.shared.log(
                "partial · CEILING len=\(partial.count) > \(partialStringCeiling) · force-final",
                category: "asr"
            )
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
    ///
    /// Defensive cumulative-vs-fragment merge:
    /// FluidAudio's EOU callback returns the latest *utterance* recognized
    /// by Parakeet, which under fast continuous speech (no 2 s silence to
    /// trigger earlier EOU) can be just the last sub-utterance fragment
    /// — e.g. two words — while our cumulative `currentPartial` holds the
    /// full running text we've been showing in the UI for the past minute.
    /// If the cumulative is meaningfully longer than `finalText`, prefer
    /// it: losing 58 seconds of accurate transcription to keep two words
    /// is the wrong trade. Worst case if FluidAudio's `finalText` *is*
    /// already the cumulative: we commit `currentPartial` which is the
    /// same thing modulo trailing punctuation. No data loss either way.
    private func emitFinal(_ finalText: String) {
        let textToCommit: String
        let usedPartial: Bool
        if currentPartial.count > finalText.count + 20 {
            textToCommit = currentPartial
            usedPartial = true
        } else {
            textToCommit = finalText
            usedPartial = false
        }
        DiagnosticsLogger.shared.log(
            "final · finalLen=\(finalText.count) partialLen=\(currentPartial.count) committedLen=\(textToCommit.count) usedPartial=\(usedPartial) text=\"\(String(textToCommit.prefix(60)))\"",
            category: "asr"
        )
        continuation?.yield(
            RecognitionUpdate(text: textToCommit, isFinal: true, timestamp: Date()))
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
