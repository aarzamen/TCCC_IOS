import Foundation

/// Chooses request boundaries without treating a UI timer as a speech pause.
/// The quiet threshold is an acoustic gate, not a clinical or voice classifier.
/// An unsafe budget boundary keeps the request as review-only evidence; capture
/// can continue in the successor request without joining unrelated text.
public struct SpeechRequestBoundary: Sendable {
    public enum Decision: Equatable, Sendable {
        case keepListening
        case finalize
        case incomplete
    }

    private var requested = false
    private var hypothesis = ""
    private var hypothesisChangedAt: TimeInterval
    private var quietDuration: TimeInterval = 0
    private var audioDuration: TimeInterval = 0
    private var lastAudioEnd: TimeInterval?

    private static let quietRMS: Float = 0.008
    private static let requiredQuiet: TimeInterval = 1
    private static let requiredStability: TimeInterval = 2.5
    private static let maximumAudio: TimeInterval = 55

    public init(openedAt: TimeInterval) {
        hypothesisChangedAt = openedAt.isFinite && openedAt >= 0 ? openedAt : .infinity
    }

    public mutating func requestRotation() { requested = true }

    public mutating func observeHypothesis(_ text: String, at now: TimeInterval) {
        guard text != hypothesis else { return }
        hypothesis = text
        hypothesisChangedAt = now.isFinite && now >= 0 ? now : .infinity
    }

    /// Supply actual appended PCM duration and the uptime of its first sample.
    /// Counting pre-roll toward the budget does not make old silence current.
    public mutating func observeAudio(
        rms: Float, duration: TimeInterval, capturedAt: TimeInterval
    ) {
        guard duration.isFinite, duration > 0 else {
            quietDuration = 0
            lastAudioEnd = nil
            return
        }
        audioDuration += duration
        guard rms.isFinite, rms >= 0, capturedAt.isFinite, capturedAt >= 0,
              (capturedAt + duration).isFinite else {
            quietDuration = 0
            lastAudioEnd = nil
            return
        }
        // A gap or reordered buffer invalidates the contiguous quiet window.
        if let lastAudioEnd, abs(capturedAt - lastAudioEnd) > 0.1 {
            quietDuration = 0
        }
        lastAudioEnd = capturedAt + duration
        quietDuration = rms <= Self.quietRMS ? min(quietDuration + duration, 5) : 0
    }

    public func decision(at now: TimeInterval) -> Decision {
        let nearBudget = audioDuration >= Self.maximumAudio - 5
        if requested || nearBudget, now.isFinite, let lastAudioEnd,
           now >= lastAudioEnd - 0.05, now - lastAudioEnd <= 0.35,
           quietDuration >= Self.requiredQuiet,
           now - hypothesisChangedAt >= Self.requiredStability {
            return .finalize
        }
        if audioDuration >= Self.maximumAudio { return .incomplete }
        return .keepListening
    }
}
