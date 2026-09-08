import Foundation
import Speech

/// Transcribes an audio file through the on-device SFSpeechRecognizer using
/// the shared production configuration (SpeechRequestFactory) — same
/// recognizer and same `requiresOnDeviceRecognition` as live capture. Uses
/// `SFSpeechURLRecognitionRequest`, the API designed for whole-file
/// transcription; buffer requests (the live-mic path) silently drop
/// faster-than-real-time file feeds and yield no results. The true live
/// buffer pipeline is exercised separately by the acoustic replay procedure.
///
/// Every callback, timeout, and cancellation decision flows through one
/// run-scoped `SpeechFileRunState`, so stale events from a finished run can
/// never complete or contaminate a newer one. Terminal outcomes — recognizer
/// finalization, timeout, error, caller cancellation — all return a
/// `Completion` describing the retained evidence; only setup failures throw.
actor AppleSpeechFileTranscriber {
    enum BenchError: Error, LocalizedError {
        case recognizerUnavailable
        case onDeviceUnavailable
        case overlappingRun
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: "SFSpeechRecognizer unavailable"
            case .onDeviceUnavailable: "On-device recognition unsupported here"
            case .overlappingRun: "A transcription run is already in flight"
            }
        }
    }

    private let recognizer: SFSpeechRecognizer?
    private var run: SpeechFileRunState?
    private var continuation: CheckedContinuation<SpeechFileRunState.Completion, Error>?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private struct Callback: Sendable {
        let text: String?
        let isFinal: Bool
        let reason: String?
        let timestamp: Date
        let speechStart: TimeInterval?
        let speechDuration: TimeInterval?
        let segmentStart: TimeInterval?
        let segmentEnd: TimeInterval?
    }
    private var callbackTask: Task<Void, Never>?
    private var callbackContinuation: AsyncStream<Callback>.Continuation?

    /// Hard cap so a recognizer that never delivers `isFinal` can't leak the
    /// continuation. The timed-out completion retains any partial text but
    /// is explicitly marked incomplete.
    private let timeout: TimeInterval = 180

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    func transcribe(fileURL: URL) async throws -> SpeechFileRunState.Completion {
        guard let recognizer, recognizer.isAvailable else { throw BenchError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw BenchError.onDeviceUnavailable }

        let started: SpeechFileRunState
        switch SpeechFileRunState.begin(replacing: run, at: Date()) {
        case .started(let fresh): started = fresh
        case .rejectedActiveRun: throw BenchError.overlappingRun
        }
        run = started
        let runID = started.runID

        // Caller already cancelled: report an explicit cancelled completion
        // without starting recognition.
        if Task.isCancelled, let completion = apply({ $0.cancel(runID: runID, at: Date()) }) {
            return completion
        }

        let request = SpeechRequestFactory.makeURLRequest(url: fileURL)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SpeechFileRunState.Completion, Error>) in
                self.continuation = cont
                // SFSpeechRecognitionResult is not Sendable — extract Sendable
                // values (String/Bool) inside the @Sendable callback before
                // hopping back onto the actor. A single callback may carry a
                // result, an error, or both; the run state decides.
                let (callbacks, callbackContinuation) = AsyncStream<Callback>.makeStream()
                self.callbackContinuation = callbackContinuation
                self.callbackTask = Task { [weak self] in
                    for await callback in callbacks {
                        guard !Task.isCancelled else { break }
                        await self?.handleCallback(callback, runID: runID)
                    }
                }
                self.task = recognizer.recognitionTask(with: request) { result, error in
                    guard result != nil || error != nil else { return }
                    callbackContinuation.yield(Callback(text: result?.bestTranscription.formattedString,
                        isFinal: result?.isFinal ?? false, reason: error?.localizedDescription,
                        timestamp: Date(), speechStart: result?.speechRecognitionMetadata?.speechStartTimestamp,
                        speechDuration: result?.speechRecognitionMetadata?.speechDuration,
                        segmentStart: result?.bestTranscription.segments.first?.timestamp,
                        segmentEnd: result?.bestTranscription.segments.last.map { $0.timestamp + $0.duration }))
                }
                self.timeoutTask = Task { [weak self, timeout] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    } catch {
                        return  // cancelled timer exits — it must never fire a timeout
                    }
                    guard !Task.isCancelled else { return }
                    await self?.handleTimeout(runID: runID)
                }
            }
        } onCancel: {
            // Caller Task cancellation routes through the same run-scoped
            // state as every other terminal event.
            Task { [weak self] in await self?.handleCancel(runID: runID) }
        }
    }

    private func handleCallback(_ callback: Callback, runID: UUID) {
        if let completion = apply({
            $0.ingestCallback(text: callback.text, isFinal: callback.isFinal, errorReason: callback.reason,
                runID: runID, at: callback.timestamp, speechStart: callback.speechStart,
                speechDuration: callback.speechDuration, segmentStart: callback.segmentStart,
                segmentEnd: callback.segmentEnd)
        }) {
            finish(completion)
        }
    }

    private func handleTimeout(runID: UUID) {
        if let completion = apply({ $0.fireTimeout(runID: runID, at: Date()) }) {
            finish(completion)
        }
    }

    private func handleCancel(runID: UUID) {
        if let completion = apply({ $0.cancel(runID: runID, at: Date()) }) {
            finish(completion)
        }
    }

    /// Route an event through the current run's state; stale or
    /// post-completion events come back nil and mutate nothing.
    private func apply(
        _ event: (inout SpeechFileRunState) -> SpeechFileRunState.Completion?
    ) -> SpeechFileRunState.Completion? {
        guard var current = run else { return nil }
        let completion = event(&current)
        run = current
        return completion
    }

    /// Resume the continuation exactly once and tear down this run's
    /// recognizer task and timer.
    private func finish(_ completion: SpeechFileRunState.Completion) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        task?.cancel(); task = nil
        callbackContinuation?.finish(); callbackContinuation = nil
        callbackTask?.cancel(); callbackTask = nil
        cont.resume(returning: completion)
    }
}
