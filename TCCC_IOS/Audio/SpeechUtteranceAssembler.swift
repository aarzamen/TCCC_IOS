import Foundation

/// Assembles a cumulative transcript from Apple Speech recognition callbacks
/// for the lifetime of one recognizer request.
///
/// On-device evidence: long requests reset the volatile hypothesis at utterance
/// boundaries. The boundary is signaled by a callback carrying valid speech
/// metadata (finite start, positive finite duration), whose text is the
/// recognizer's full hypothesis for that timing window; the next callback
/// restarts from one word. A plain replace-on-callback consumer loses every
/// earlier utterance.
///
/// Rules, from the observed callback stream:
/// - Callbacks without valid metadata are volatile revisions of the current
///   utterance and replace the active partial (zero segment times carry no
///   stale-evidence meaning).
/// - A callback with valid metadata finalizes its window. Boundaries come only
///   from timing evidence, never from text shortening or prefix/word equality,
///   so genuinely repeated utterances are retained.
/// - A timed window extending past the last finalized window starts a new
///   utterance; any earlier finalized windows it fully covers are replaced by
///   its cumulative text rather than duplicated.
/// - A timed window ending at or before the last finalized window is an echo or
///   correction of already-finalized speech: it replaces the finalized
///   utterances it cleanly covers (identical text is a no-op) and is otherwise
///   ignored. It never appends stale text or erases the active partial.
/// - Nil/empty callbacks preserve evidence; invalid timing cannot create a boundary.
///
/// Clinical extraction remains outside this helper, at request isFinal.
struct SpeechUtteranceAssembler: Sendable {
    private struct Utterance: Sendable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    /// Allow timing jitter when identifying the same window. New non-overlapping
    /// windows take priority, even for very short utterances.
    private static let tolerance: TimeInterval = 0.25

    private var finalized: [Utterance] = []
    private var activePartial: String = ""

    var transcript: String {
        var parts = finalized.map(\.text)
        if !activePartial.isEmpty { parts.append(activePartial) }
        return parts.joined(separator: " ")
    }

    init() {}

    mutating func ingest(
        text: String?,
        speechStart: TimeInterval? = nil,
        speechDuration: TimeInterval? = nil,
        segmentStart: TimeInterval? = nil,
        segmentEnd: TimeInterval? = nil
    ) {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let window = Self.validWindow(start: speechStart, duration: speechDuration) else {
            activePartial = trimmed
            return
        }
        ingestTimed(trimmed, window: window)
    }

    private static func validWindow(
        start: TimeInterval?, duration: TimeInterval?
    ) -> (start: TimeInterval, end: TimeInterval)? {
        guard let start, let duration,
              start.isFinite, duration.isFinite,
              start >= 0, duration > 0, (start + duration).isFinite else { return nil }
        return (start, start + duration)
    }

    private mutating func ingestTimed(
        _ text: String, window: (start: TimeInterval, end: TimeInterval)
    ) {
        // A forward non-overlapping window cannot correct earlier speech.
        // Do this before tolerant containment, which could otherwise swallow
        // a preceding short utterance such as "no".
        if let last = finalized.last, window.start >= last.end {
            finalized.append(Utterance(text: text, start: window.start, end: window.end))
            activePartial = ""
            return
        }
        let covered = coveredRange(by: window)
        if let last = finalized.last, window.end <= last.end + Self.tolerance {
            // Echo/correction of already-finalized speech; the active partial
            // belongs to newer speech and must survive untouched.
            guard let covered else { return }
            finalized.replaceSubrange(
                covered, with: [Utterance(text: text, start: window.start, end: window.end)])
            return
        }
        // New utterance boundary: this text is the full hypothesis for the
        // window and supersedes the active partial plus any finalized
        // utterances the window cumulatively covers.
        if let covered { finalized.removeSubrange(covered) }
        finalized.append(Utterance(text: text, start: window.start, end: window.end))
        activePartial = ""
    }

    /// Finalized utterances fully contained in the window (± tolerance).
    /// Windows are stored in time order, so containment selects a contiguous run.
    private func coveredRange(by window: (start: TimeInterval, end: TimeInterval)) -> Range<Int>? {
        let indices = finalized.indices.filter {
            finalized[$0].start >= window.start - Self.tolerance
                && finalized[$0].end <= window.end + Self.tolerance
        }
        guard let first = indices.first, let last = indices.last else { return nil }
        return first..<(last + 1)
    }
}
