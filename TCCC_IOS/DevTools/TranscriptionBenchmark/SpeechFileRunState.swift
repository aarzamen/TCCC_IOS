import Foundation

/// Run-scoped state machine for one file-transcription attempt. Every
/// recognizer callback, timeout, and cancellation decision made by
/// `AppleSpeechFileTranscriber` flows through this value, so the lifecycle
/// rules are deterministic and testable without the Speech framework:
///
/// - exactly one completion per run; later events are inert;
/// - events carrying a stale run ID cannot touch a newer run;
/// - cumulative hypotheses replace, never concatenate;
/// - timeout/error/cancellation retain partial text but are never reported
///   as recognizer finalization;
/// - a callback carrying both a result and an error keeps the text as
///   evidence and reports the failure.
struct SpeechFileRunState: Sendable {
    enum Termination: String, Codable, Sendable {
        /// The recognizer delivered `isFinal`. Finalization evidence only —
        /// it does not prove every spoken word in the file was captured.
        case finalized
        case timedOut
        case failed
        case cancelled
    }

    /// Completion evidence surfaced for every run, including failed and
    /// empty ones, so the benchmark can persist a truthful artifact.
    struct Completion: Sendable, Equatable {
        let termination: Termination
        /// Latest cumulative hypothesis at termination; may be empty.
        let transcript: String
        /// True only for `.finalized` — recognizer finalization evidence,
        /// never proof of whole-file coverage.
        let isComplete: Bool
        let failureReason: String?
        /// Recognizer callbacks this run accepted (results and errors).
        let callbackCount: Int
        let startedAt: Date
        let firstHypothesisAt: Date?
        let lastHypothesisAt: Date?
        let finishedAt: Date
    }

    enum BeginResult {
        case started(SpeechFileRunState)
        case rejectedActiveRun(activeRunID: UUID)
    }

    let runID: UUID
    let startedAt: Date
    private(set) var callbackCount = 0
    private(set) var latestHypothesis = ""
    private(set) var firstHypothesisAt: Date?
    private(set) var lastHypothesisAt: Date?
    private(set) var completion: Completion?

    private init(runID: UUID, startedAt: Date) {
        self.runID = runID
        self.startedAt = startedAt
    }

    /// Start a run. An unfinished previous run is rejected untouched — an
    /// overlapping transcribe must not overwrite in-flight evidence.
    static func begin(replacing previous: SpeechFileRunState?, at now: Date) -> BeginResult {
        if let previous, previous.completion == nil {
            return .rejectedActiveRun(activeRunID: previous.runID)
        }
        return .started(SpeechFileRunState(runID: UUID(), startedAt: now))
    }

    /// Single decision point for a live recognizer callback, which may carry
    /// a result, an error, or both. Simultaneous result + error keeps the
    /// text as evidence but reports the failure — a final flag cannot
    /// silently override an error delivered with it.
    mutating func ingestCallback(
        text: String?, isFinal: Bool, errorReason: String?, runID: UUID, at now: Date
    ) -> Completion? {
        guard accepts(runID) else { return nil }
        if let errorReason {
            note(text: text, at: now)
            return complete(.failed, failureReason: errorReason, at: now)
        }
        guard let text else { return nil }
        return ingestHypothesis(text, isFinal: isFinal, runID: runID, at: now)
    }

    mutating func ingestHypothesis(
        _ text: String, isFinal: Bool, runID: UUID, at now: Date
    ) -> Completion? {
        guard accepts(runID) else { return nil }
        note(text: text, at: now)
        return isFinal ? complete(.finalized, failureReason: nil, at: now) : nil
    }

    mutating func ingestError(reason: String, runID: UUID, at now: Date) -> Completion? {
        guard accepts(runID) else { return nil }
        note(text: nil, at: now)
        return complete(.failed, failureReason: reason, at: now)
    }

    mutating func fireTimeout(runID: UUID, at now: Date) -> Completion? {
        guard accepts(runID) else { return nil }
        return complete(.timedOut, failureReason: nil, at: now)
    }

    mutating func cancel(runID: UUID, at now: Date) -> Completion? {
        guard accepts(runID) else { return nil }
        return complete(.cancelled, failureReason: nil, at: now)
    }

    private func accepts(_ eventRunID: UUID) -> Bool {
        eventRunID == runID && completion == nil
    }

    private mutating func note(text: String?, at now: Date) {
        callbackCount += 1
        if text != nil {
            if firstHypothesisAt == nil { firstHypothesisAt = now }
            lastHypothesisAt = now
        }
        // Cumulative hypotheses replace; an empty late one erases nothing.
        if let text, !text.isEmpty { latestHypothesis = text }
    }

    private mutating func complete(
        _ termination: Termination, failureReason: String?, at now: Date
    ) -> Completion {
        let done = Completion(
            termination: termination,
            transcript: latestHypothesis,
            isComplete: termination == .finalized,
            failureReason: failureReason,
            callbackCount: callbackCount,
            startedAt: startedAt,
            firstHypothesisAt: firstHypothesisAt,
            lastHypothesisAt: lastHypothesisAt,
            finishedAt: now)
        completion = done
        return done
    }
}
