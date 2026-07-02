import Foundation
import Speech
import AVFoundation

/// Feeds an audio file through the on-device SFSpeechRecognizer using the
/// SAME request configuration as production capture (SpeechRequestFactory),
/// re-arming a fresh request whenever the recognizer finalizes mid-file —
/// mirroring SpeechRecognizer.handleFinalResult's continuous-narration
/// behavior. File-ingestion mode: deterministic input, no mic, no DSP.
actor AppleSpeechFileTranscriber {
    struct Output: Sendable {
        let finals: [String]
        let firstPartialLatencySec: Double?
        let wallTimeSec: Double
    }

    enum BenchError: Error, LocalizedError {
        case recognizerUnavailable
        case onDeviceUnavailable
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: "SFSpeechRecognizer unavailable"
            case .onDeviceUnavailable: "On-device recognition unsupported here"
            }
        }
    }

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finals: [String] = []
    private var firstPartialAt: Date?
    private var lastResultAt: Date = .distantPast
    private var sawError = false
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func transcribe(fileURL: URL) async throws -> Output {
        guard let recognizer, recognizer.isAvailable else { throw BenchError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw BenchError.onDeviceUnavailable }

        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let started = Date()
        armRequest()

        // Feed the whole file (faster than real time — model comparison
        // mode; latency figures here are ingest-relative, not real-time).
        let chunkFrames: AVAudioFrameCount = 4096
        while file.framePosition < file.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { break }
            try file.read(into: buf, frameCount: chunkFrames)
            if buf.frameLength == 0 { break }
            request?.append(buf)
            // Yield so recognition callbacks interleave with feeding.
            await Task.yield()
        }
        request?.endAudio()

        // Wait for the recognizer to drain: done when no new result has
        // arrived for 3s after end-of-audio, or 60s hard cap.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if sawError { break }
            if lastResultAt != .distantPast, Date().timeIntervalSince(lastResultAt) > 3.0 { break }
            if lastResultAt == .distantPast, Date().timeIntervalSince(started) > 30 { break }
        }
        task?.cancel()
        task = nil
        request = nil

        return Output(
            finals: finals,
            firstPartialLatencySec: firstPartialAt.map { $0.timeIntervalSince(started) },
            wallTimeSec: Date().timeIntervalSince(started)
        )
    }

    // NOTE: the recognition callback must NOT capture the (non-Sendable)
    // SFSpeechRecognizer — strict concurrency. It reaches it back through
    // the actor property inside handle().
    private func armRequest() {
        guard let recognizer else { return }
        let req = SpeechRequestFactory.makeBufferRequest()
        self.request = req
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { await self.handle(text: text, isFinal: isFinal) }
            } else if error != nil {
                Task { await self.noteError() }
            }
        }
    }

    private func handle(text: String, isFinal: Bool) {
        lastResultAt = Date()
        if firstPartialAt == nil { firstPartialAt = Date() }
        if isFinal {
            if !text.isEmpty { finals.append(text) }
            // Mid-file finalization: re-arm so the rest of the audio lands
            // in a fresh request (production parity).
            if request != nil {
                request?.endAudio()
                armRequest()
            }
        }
    }

    private func noteError() {
        sawError = true
    }
}
