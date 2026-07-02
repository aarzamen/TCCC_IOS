import Foundation
import Speech

/// Transcribes an audio file through the on-device SFSpeechRecognizer using
/// the shared production configuration (SpeechRequestFactory) — same
/// recognizer and same `requiresOnDeviceRecognition` as live capture. Uses
/// `SFSpeechURLRecognitionRequest`, the API designed for whole-file
/// transcription; buffer requests (the live-mic path) silently drop
/// faster-than-real-time file feeds and yield no results. The true live
/// buffer pipeline is exercised separately by the acoustic replay procedure.
actor AppleSpeechFileTranscriber {
    struct Output: Sendable {
        let finals: [String]
        let firstPartialLatencySec: Double?
        let wallTimeSec: Double
    }

    enum BenchError: Error, LocalizedError {
        case recognizerUnavailable
        case onDeviceUnavailable
        case recognitionFailed(String)
        case timedOut
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: "SFSpeechRecognizer unavailable"
            case .onDeviceUnavailable: "On-device recognition unsupported here"
            case .recognitionFailed(let r): "Recognition failed: \(r)"
            case .timedOut: "Recognition timed out"
            }
        }
    }

    private let recognizer: SFSpeechRecognizer?
    private var continuation: CheckedContinuation<Output, Error>?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var bestFinal = ""
    private var firstPartialAt: Date?
    private var started = Date()

    /// Hard cap so a recognizer that never delivers `isFinal` can't leak the
    /// continuation. If partials arrived, return them; otherwise fail.
    private let timeout: TimeInterval = 180

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func transcribe(fileURL: URL) async throws -> Output {
        guard let recognizer, recognizer.isAvailable else { throw BenchError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw BenchError.onDeviceUnavailable }
        started = Date()
        bestFinal = ""
        firstPartialAt = nil

        let request = SpeechRequestFactory.makeURLRequest(url: fileURL)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Output, Error>) in
            self.continuation = cont
            // SFSpeechRecognitionResult is not Sendable — extract Sendable
            // values (String/Bool) inside the @Sendable callback before hopping
            // back onto the actor.
            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    Task { await self.ingest(text: text, isFinal: isFinal) }
                } else if let error {
                    let reason = error.localizedDescription
                    Task { await self.fail(reason: reason) }
                }
            }
            self.timeoutTask = Task { [weak self, timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.fireTimeout()
            }
        }
    }

    private func ingest(text: String, isFinal: Bool) {
        if firstPartialAt == nil { firstPartialAt = Date() }
        if !text.isEmpty { bestFinal = text }
        if isFinal { finish(.success(makeOutput())) }
    }

    private func fail(reason: String) {
        // If partials already arrived, treat a late error as end-of-audio and
        // keep what we have; otherwise surface the failure.
        if bestFinal.isEmpty {
            finish(.failure(BenchError.recognitionFailed(reason)))
        } else {
            finish(.success(makeOutput()))
        }
    }

    private func fireTimeout() {
        if bestFinal.isEmpty {
            finish(.failure(BenchError.timedOut))
        } else {
            finish(.success(makeOutput()))
        }
    }

    private func makeOutput() -> Output {
        Output(
            finals: bestFinal.isEmpty ? [] : [bestFinal],
            firstPartialLatencySec: firstPartialAt.map { $0.timeIntervalSince(started) },
            wallTimeSec: Date().timeIntervalSince(started)
        )
    }

    /// Resume the continuation exactly once and tear down.
    private func finish(_ result: Result<Output, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        task?.cancel(); task = nil
        switch result {
        case .success(let output): cont.resume(returning: output)
        case .failure(let error): cont.resume(throwing: error)
        }
    }
}
