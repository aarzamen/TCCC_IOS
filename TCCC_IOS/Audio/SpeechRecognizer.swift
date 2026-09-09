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

    // MARK: - Pre-roll ring buffer (last 30s of PCM — see leadDuration)

    private var ringBuffer: [AVAudioPCMBuffer] = []
    private var ringBufferFrames: Int = 0

    // MARK: - Recognition

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var isRecognizing: Bool = false
    private var capture: CaptureRequestState?
    private var tailTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var queuedAudio: [AVAudioPCMBuffer] = []
    private var queuedFrames = 0
    private var latestText = ""
    private var utterances = SpeechUtteranceAssembler()
    private var requestStartedAt: TimeInterval = 0
    private struct Callback: Sendable {
        let text: String?
        let final: Bool
        let issue: String?
        let speechStart: TimeInterval?
        let speechDuration: TimeInterval?
        let segmentStart: TimeInterval?
        let segmentEnd: TimeInterval?
    }
    private var resultConsumer: Task<Void, Never>?
    private var resultContinuation: AsyncStream<Callback>.Continuation?
    private var audioConsumer: Task<Void, Never>?
    private var audioContinuation: AsyncStream<CapturedPCM>.Continuation?
    private var tapGeneration = UUID()
    private var captureStartedAt = Date.distantFuture

    /// Each tap buffer is copied once and then owned by the serial consumer.
    private struct CapturedPCM: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

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
        let speechStatus = await SpeechAuthorization.request()
        guard speechStatus == .authorized else {
            throw TranscriptStreamError.speechDenied
        }

        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { @Sendable granted in cont.resume(returning: granted) }
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

        // iOS Voice Processing IO Unit: AGC + AEC + noise suppression on
        // the input node, applied BEFORE the tap fires. This is the
        // adaptive-gain layer the operator asked for — iOS tracks ambient
        // RMS and pushes speech toward ~-16 dBFS with attack/release tuned
        // for voice. The manual gain slider (`gainProvider`) still applies
        // as a multiplicative trim on top, so a quiet medic in a noisy
        // field gets boosted automatically without fighting a Settings
        // slider mid-narration. setVoiceProcessingEnabled must run BEFORE
        // installTap and BEFORE engine.start, and is documented to throw
        // on some devices/sessions — fall back silently to hardware-unity
        // capture if it fails.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            inputNode.isVoiceProcessingAGCEnabled = true
        } catch {
            // Best-effort — capture continues at hardware unity gain.
        }

        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        let weakLevels = self.levels
        let (audioStream, audioContinuation) = AsyncStream<CapturedPCM>.makeStream(bufferingPolicy: .bufferingOldest(128))
        self.audioContinuation = audioContinuation
        let generation = UUID()
        tapGeneration = generation
        audioConsumer = Task { [weak self] in
            for await frame in audioStream {
                guard !Task.isCancelled else { break }
                await self?.ingestBuffer(frame.buffer, generation: generation)
            }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let copy = Self.copyBuffer(buffer) else { return }
            let rms = Self.computeRMS(buffer)
            if let weakLevels {
                Task { @MainActor in weakLevels.ingest(rms) }
            }
            if case .dropped = audioContinuation.yield(CapturedPCM(buffer: copy)) {
                let droppedAt = Date()
                Task { [weak self] in await self?.audioOverrun(generation: generation, at: droppedAt) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioContinuation.finish()
            audioConsumer?.cancel()
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }
        isPrimed = true
    }

    /// Stop the audio engine + tap. Tears down any in-flight recognizer.
    func unprime() async {
        if isRecognizing { finishCapture(.cancelled, issue: "Capture interrupted") }
        audioContinuation?.finish(); audioContinuation = nil
        audioConsumer?.cancel(); audioConsumer = nil
        tapGeneration = UUID()
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
        if !isPrimed { try await prime() }
        guard !isRecognizing else { throw TranscriptStreamError.alreadyRunning }
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptStreamError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptStreamError.onDeviceUnavailable
        }
        lastRecordingURL = nil
        if let audioURL, let format = inputFormat {
            do {
                try ProtectedWrite.createEmpty(at: audioURL)
                audioFile = try AVAudioFile(forWriting: audioURL,
                    settings: AudioCaptureConfig.aacOutputSettings,
                    commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                lastRecordingURL = audioURL
            } catch {
                audioFile = nil
                throw TranscriptStreamError.engineFailed("Cannot save audio: \(error.localizedDescription)")
            }
        }
        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        capture = CaptureRequestState()
        captureStartedAt = Date()
        queuedAudio.removeAll(); queuedFrames = 0
        isRecognizing = true
        beginRequest()
        for buffer in ringBuffer {
            request?.append(buffer)
            writeAudio(buffer)
        }
        return stream
    }

    func stop() async {
        guard let capture, !capture.closed, tailTask == nil else { return }
        let captureID = capture.captureID
        tailTask = Task { [weak self, tailDuration] in
            do { try await Task.sleep(for: .seconds(tailDuration)) } catch { return }
            await self?.endTail(captureID: captureID)
        }
    }

    func stopImmediate() async {
        finishCapture(.cancelled, issue: "Capture interrupted; unfinished speech retained for review")
    }

    /// A debounce/periodic boundary requests a final result; incoming frames
    /// wait for the successor rather than being appended to an ended request.
    func forceFinalize() async { endRequest() }

    private func endRequest() {
        guard capture?.endRequest() == true, let capture else { return }
        request?.endAudio()
        let requestID = capture.requestID
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await self?.drainTimedOut(requestID: requestID)
        }
    }

    private func endTail(captureID: UUID) {
        guard capture?.captureID == captureID, capture?.closed == false else { return }
        capture?.endTail()
        endRequest()
    }

    private func drainTimedOut(requestID: UUID) {
        guard capture?.accepts(requestID) == true else { return }
        finishCapture(.timedOut, issue: "Recognition finalization timed out; audio retained")
    }

    private func ingestBuffer(_ buffer: AVAudioPCMBuffer, generation: UUID) {
        guard generation == tapGeneration else { return }
        let gain = gainProvider()
        if gain != 1.0 { Self.applyGain(buffer, gain: gain) }
        ringBuffer.append(buffer)
        ringBufferFrames += Int(buffer.frameLength)
        let maxFrames = Int(leadDuration * buffer.format.sampleRate)
        while ringBufferFrames > maxFrames, !ringBuffer.isEmpty {
            ringBufferFrames -= Int(ringBuffer.removeFirst().frameLength)
        }
        guard isRecognizing, let capture, !capture.tailExpired else { return }
        writeAudio(buffer)
        if capture.awaitingFinal {
            queuedAudio.append(buffer)
            queuedFrames += Int(buffer.frameLength)
            if queuedFrames > Int(10 * buffer.format.sampleRate) {
                finishCapture(.failed, issue: "Recognition fell behind; saved audio needs review")
            }
        } else {
            request?.append(buffer)
        }
    }

    private func audioOverrun(generation: UUID, at date: Date) {
        guard generation == tapGeneration, date >= captureStartedAt else { return }
        finishCapture(.failed, issue: "Audio capture could not keep up; recording is incomplete")
    }

    private func writeAudio(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }
        do { try file.write(from: buffer) }
        catch {
            audioFile = nil
            lastRecordingURL = nil
            continuation?.yield(RecognitionUpdate(text: "", isFinal: false, timestamp: Date(),
                captureID: capture?.captureID, requestID: capture?.requestID,
                issue: "Audio save failed: \(error.localizedDescription)", audioUnavailable: true))
        }
    }

    private func beginRequest() {
        guard let capture, !capture.closed, let recognizer else { return }
        latestText = ""
        utterances = SpeechUtteranceAssembler()
        requestStartedAt = ProcessInfo.processInfo.systemUptime
        let requestID = capture.requestID
        let req = SpeechRequestFactory.makeBufferRequest()
        request = req
        resultContinuation?.finish()
        resultConsumer?.cancel()
        let (callbacks, callbackContinuation) = AsyncStream<Callback>.makeStream()
        resultContinuation = callbackContinuation
        resultConsumer = Task { [weak self] in
            for await callback in callbacks {
                guard !Task.isCancelled else { break }
                await self?.handleResult(callback, requestID: requestID)
            }
        }
        task = recognizer.recognitionTask(with: req) { result, error in
            callbackContinuation.yield(Callback(text: result?.bestTranscription.formattedString,
                final: result?.isFinal ?? false, issue: error?.localizedDescription,
                speechStart: result?.speechRecognitionMetadata?.speechStartTimestamp,
                speechDuration: result?.speechRecognitionMetadata?.speechDuration,
                segmentStart: result?.bestTranscription.segments.first?.timestamp,
                segmentEnd: result?.bestTranscription.segments.last.map { $0.timestamp + $0.duration }))
        }
    }

    private func handleResult(_ callback: Callback, requestID: UUID) {
        guard capture?.accepts(requestID) == true else { return }
        utterances.ingest(text: callback.text, speechStart: callback.speechStart,
            speechDuration: callback.speechDuration, segmentStart: callback.segmentStart,
            segmentEnd: callback.segmentEnd)
        latestText = utterances.transcript
        if let issue = callback.issue {
            finishCapture(.failed, issue: "Recognition incomplete: \(issue)")
            return
        }
        if callback.final {
            emit(.finalized)
            drainTask?.cancel(); drainTask = nil
            request?.endAudio()
            task = nil; request = nil
            guard capture?.finalized(requestID, hasBufferedAudio: !queuedAudio.isEmpty) == true else {
                finishCapture(nil)
                return
            }
            beginRequest()
            for buffer in queuedAudio { request?.append(buffer) }
            queuedAudio.removeAll(); queuedFrames = 0
            if capture?.tailExpired == true { endRequest() }
        } else {
            continuation?.yield(RecognitionUpdate(text: latestText, isFinal: false, timestamp: Date(),
                captureID: capture?.captureID, requestID: requestID, requestStartedAt: requestStartedAt))
        }
    }

    private func emit(_ termination: CaptureTermination, issue: String? = nil) {
        continuation?.yield(RecognitionUpdate(text: latestText, isFinal: termination == .finalized,
            timestamp: Date(), captureID: capture?.captureID, requestID: capture?.requestID,
            termination: termination, issue: issue, requestStartedAt: requestStartedAt))
    }

    private func finishCapture(_ termination: CaptureTermination?, issue: String? = nil) {
        guard isRecognizing else { return }
        if let termination { emit(termination, issue: issue) }
        capture?.close()
        isRecognizing = false
        tailTask?.cancel(); tailTask = nil
        drainTask?.cancel(); drainTask = nil
        request?.endAudio()
        task?.cancel(); task = nil; request = nil
        resultContinuation?.finish(); resultContinuation = nil
        resultConsumer?.cancel(); resultConsumer = nil
        queuedAudio.removeAll(); queuedFrames = 0
        audioFile = nil
        if let url = lastRecordingURL {
            do { try ProtectedWrite.markProtected(at: url) }
            catch {
                lastRecordingURL = nil
                continuation?.yield(RecognitionUpdate(text: "", isFinal: false, timestamp: Date(),
                    issue: "Audio protection failed: \(error.localizedDescription)", audioUnavailable: true))
            }
        }
        continuation?.finish(); continuation = nil
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
