import Foundation

/// The live adapter's request boundary. Finishing an utterance is distinct
/// from ending capture: STOP first allows its tail, then drains final results.
struct CaptureRequestState: Sendable {
    let captureID = UUID()
    private(set) var requestID = UUID()
    private(set) var awaitingFinal = false
    private(set) var tailExpired = false
    private(set) var closed = false

    func accepts(_ id: UUID) -> Bool { !closed && id == requestID }

    mutating func endRequest() -> Bool {
        guard !closed, !awaitingFinal else { return false }
        awaitingFinal = true
        return true
    }

    mutating func endTail() { tailExpired = true }

    /// nil rejects a stale callback; true starts the successor, false ends capture.
    /// Buffered audio from the ended request is drained even after the tail expires.
    mutating func finalized(_ id: UUID, hasBufferedAudio: Bool) -> Bool? {
        guard accepts(id) else { return nil }
        if tailExpired && !hasBufferedAudio {
            closed = true
            return false
        }
        requestID = UUID()
        awaitingFinal = false
        return true
    }

    @discardableResult mutating func close() -> Bool {
        guard !closed else { return false }
        closed = true
        return true
    }
}
