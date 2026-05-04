import Foundation
import Speech
@preconcurrency import AVFAudio

actor SpeechRecognizer: TranscriptStream {
    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private weak var levels: AudioLevels?

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<RecognitionUpdate>.Continuation?
    private var running: Bool = false

    init(locale: Locale = Locale(identifier: "en-US"), levels: AudioLevels?) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.levels = levels
    }

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

    func start() async throws -> AsyncStream<RecognitionUpdate> {
        guard !running else { throw TranscriptStreamError.alreadyRunning }
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptStreamError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptStreamError.onDeviceUnavailable
        }

        try configureSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let weakLevels = self.levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let rms = Self.computeRMS(buffer)
            if let weakLevels {
                Task { @MainActor in
                    weakLevels.ingest(rms)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.request = nil
            throw TranscriptStreamError.engineFailed(error.localizedDescription)
        }

        let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
        self.continuation = continuation
        self.running = true

        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.emit(text: text, isFinal: isFinal) }
                if isFinal {
                    Task { await self.finishRecognitionPass() }
                }
            } else if error != nil {
                Task { await self.stop() }
            }
        }

        return stream
    }

    func stop() async {
        guard running else { return }
        running = false

        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)

        request?.endAudio()
        task?.cancel()

        request = nil
        task = nil

        continuation?.finish()
        continuation = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let weakLevels = self.levels
        if let weakLevels {
            Task { @MainActor in weakLevels.reset() }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func emit(text: String, isFinal: Bool) {
        continuation?.yield(RecognitionUpdate(text: text, isFinal: isFinal, timestamp: Date()))
    }

    private func finishRecognitionPass() async {
        guard running else { return }
        request?.endAudio()
        task = nil
        request = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        guard let recognizer else { return }
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.emit(text: text, isFinal: isFinal) }
                if isFinal {
                    Task { await self.finishRecognitionPass() }
                }
            } else if error != nil {
                Task { await self.stop() }
            }
        }
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
