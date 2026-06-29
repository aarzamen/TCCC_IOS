import Foundation
import Speech
@preconcurrency import AVFAudio

/// On-device speech recognizer with a 30-second pre-roll ring buffer and a
/// 30-second post-roll tail. Mic engine runs continuously while the recognizer
/// is "primed" — that lets the medic start narrating well before tapping
/// RECORD (typical scenario: a corpsman speaks the assessment as they
/// approach the casualty, then taps when they reach the patient), and gives
/// a generous trailing window after STOP so the final sentence — even a
/// long one with hesitation pauses — gets captured.
///
/// 30s × 16kHz × 16-bit mono ≈ 1 MB of PCM held in-memory between
/// `prime()` and the next `start()` — trivial for the iPhone's memory
/// budget.
///
/// Lifecycle:
///   prime()      — engine + tap on; ring buffer accumulates last 30s
///   start(...)   — drain ring buffer into recognizer, attach live; optionally
///                  write captured PCM to a .wav file for export
///   stop()       — schedule a 30s tail; recognizer continues, then ends
///   unprime()    — engine + tap off
///
/// All audio remains on-device. `requiresOnDeviceRecognition = true` is hard
/// requirement — RF Ghost forbids cloud transcription.
actor SpeechRecognizer: TranscriptStream {

    // MARK: - Configuration

    /// 30-second pre-roll. Matches `tailDuration` for symmetry — the medic
    /// can speak for up to 30 seconds before tapping RECORD and still have
    /// it captured, and up to 30 seconds after tapping STOP.
    private let leadDuration: TimeInterval = 30.0

    /// 30-second post-tap tail. Long enough to cover slow trailing
    /// sentences ("…maintaining airway, will reassess in five.") plus a
    /// small thinking pause.
    private let tailDuration: TimeInterval = 30.0

    // MARK: - Audio engine

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private weak var levels: AudioLevels?
    private var inputFormat: AVAudioFormat?
    private var isPrimed: Bool = false

    // MARK: - Pre-roll ring buffer (last ~10s of PCM)

    private var ringBuffer: [AVAudioPCMBuffer] = []
    private var ringBufferFrames: Int = 0

    // MARK: - Recognition

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isRecognizing: Bool = false
    private var tailDeadline: Date?

    // MARK: - Audio file capture

    private var audioFile: AVAudioFile?
    public private(set) var lastRecordingURL: URL?

    // MARK: - Init

    init(
        locale: Locale = Locale(identifier: "en-US"),
        levels: AudioLevels?,
        gainProvider: @escaping @Sendable () -> Float = { 1.0 }
    ) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.levels = levels
        self.gainProvider = gainProvider
    }

    /// Provider for the current dynamic gain multiplier (linear, not
    /// dB). Read on every audio buffer so a Settings slider change
    /// takes effect on the next sample.
    private let gainProvider: @Sendable () -> Float

    // MARK: - Authorization

    func authorize() async throws {
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw TranscriptStreamError.speechDenied
        }

        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            throw TranscriptStreamError.microphoneDenied
        }
    }

    // MARK: - Engine lifecycle

    /// Start the audio engine + tap so the ring buffer fills with the last
    /// `leadDuration` seconds of audio. The recognizer is NOT attached yet —
    /// call `start()` for that. Idempotent.
    func prime() async throws {
        guard !isPrimed else { return }
        try configureSession()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        let weakLevels = self.levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Copy out of AVAudioEngine's reusable buffer pool.
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
    }

    /// Stop the audio engine + tap. Tears down any in-flight recognizer.
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

    /// Attach the recognizer. The 30s ring buffer is drained as pre-roll, then
    /// live audio streams in. If `audioURL` is provided, captured PCM is written
    /// to that file for export — pre-roll included.
    func start(audioURL: URL? = nil) async throws -> AsyncStream<RecognitionUpdate> {
        if !isPrimed {
            try await prime()
        }
        guard !isRecognizing else { throw TranscriptStreamError.alreadyRunning }
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptStreamError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptStreamError.onDeviceUnavailable
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        // Open audio file for writing if URL provided.
        // Pre-create the file with NSFileProtectionComplete so the streamed
        // AVAudioFile writes inherit Data Protection. CLAUDE.md hard
        // constraint #3 — casualty audio at rest must be AES-256.
        if let audioURL, let format = inputFormat {
            do {
                try ProtectedWrite.createEmpty(at: audioURL)
                // AAC encode-on-write. AVFoundation handles PCM -> AAC
                // internally for .m4a output. Mirrors the Parakeet path so
                // both ASR backends produce the same voice-quality 32 kbps
                // / 16 kHz mono m4a (~25 MB/hr) regardless of which is
                // active. Shared constant lives in `AudioCaptureConfig`.
                let file = try AVAudioFile(
                    forWriting: audioURL,
                    settings: AudioCaptureConfig.aacOutputSettings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                self.audioFile = file
                self.lastRecordingURL = audioURL
            } catch {
                // Non-fatal — recognition still works, just no audio export.
                self.audioFile = nil
            }
        }

        // Drain pre-roll: feed the last 30s of buffered audio into both the
        // recognizer and the audio file.
        for buf in ringBuffer {
            req.append(buf)
            try? audioFile?.write(from: buf)
        }

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        self.tailDeadline = nil
        self.isRecognizing = true

        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.emit(text: text, isFinal: isFinal) }
                if isFinal {
                    Task { await self.handleFinalResult() }
                }
            } else if error != nil {
                Task { await self.teardownRecognizer() }
            }
        }

        return stream
    }

    /// Mark the end of recording. Schedules a `tailDuration`-second tail —
    /// the recognizer keeps consuming live audio until the tail elapses, then
    /// finalises. Engine stays primed so a subsequent `start()` is instant.
    func stop() async {
        guard isRecognizing else { return }
        if tailDeadline == nil {
            tailDeadline = Date().addingTimeInterval(tailDuration)
        }
    }

    /// Immediate tear-down without tail — error path / app backgrounded.
    func stopImmediate() async {
        await teardownRecognizer()
    }

    /// Force the current recognition request to finalise and start a fresh
    /// one. The UI calls this after committing a debounced partial — so the
    /// next stream of partials starts from a clean context, not redundantly
    /// repeating the already-committed prefix.
    func forceFinalize() async {
        guard isRecognizing else { return }
        guard tailDeadline == nil else { return }
        // End the current request — the existing task callback will fire
        // isFinal=true, which in turn calls handleFinalResult, which starts a
        // new request automatically.
        request?.endAudio()
    }

    // MARK: - Tap-callback path

    private func ingestBuffer(_ buffer: AVAudioPCMBuffer) {
        // Apply variable dynamic gain BEFORE storing/streaming so the
        // ring buffer, level meter, and ASR all see the post-gain
        // signal.
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

        request?.append(buffer)
        try? audioFile?.write(from: buffer)

        // Check tail deadline.
        if let deadline = tailDeadline, Date() >= deadline {
            Task { await self.teardownRecognizer() }
        }
    }

    // MARK: - Recognition internals

    private func emit(text: String, isFinal: Bool) {
        continuation?.yield(RecognitionUpdate(text: text, isFinal: isFinal, timestamp: Date()))
    }

    private func handleFinalResult() async {
        // If we're tearing down (tail mode), let the recognizer die.
        guard isRecognizing else { return }
        guard tailDeadline == nil else {
            await teardownRecognizer()
            return
        }

        // Continuous narration: start a fresh recognition pass.
        request?.endAudio()
        task = nil
        request = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        guard let recognizer else { return }
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.emit(text: text, isFinal: isFinal) }
                if isFinal {
                    Task { await self.handleFinalResult() }
                }
            } else if error != nil {
                Task { await self.teardownRecognizer() }
            }
        }
    }

    private func teardownRecognizer() async {
        guard isRecognizing else { return }
        isRecognizing = false
        tailDeadline = nil
        request?.endAudio()
        task = nil
        request = nil
        let closedURL = lastRecordingURL
        audioFile = nil
        // Re-mark complete protection after closing the streamed file.
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
