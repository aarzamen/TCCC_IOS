import Foundation

/// Conservative beginning of the audio represented by one recognition request.
/// A request may receive pre-roll, queued rotation audio, or delayed live frames
/// that were captured before it opened. Those words must retain their earlier
/// operator-decision fence even though the Speech framework request is new.
struct SpeechBufferClock: Sendable {
    private(set) var requestStartedAt: TimeInterval

    /// An empty request retains its live opening boundary.
    init(openedAt: TimeInterval) {
        requestStartedAt = Self.validUptime(openedAt) ? openedAt : 0
    }

    mutating func includeBuffer(capturedAt: TimeInterval) {
        // Unknown timing cannot grant permission to overwrite an operator's
        // decision. Uptime zero conservatively requires review for that request.
        guard Self.validUptime(capturedAt) else {
            requestStartedAt = 0
            return
        }
        requestStartedAt = min(requestStartedAt, capturedAt)
    }

    private static func validUptime(_ value: TimeInterval) -> Bool {
        value.isFinite && value >= 0
    }
}
