import AVFoundation
import Foundation

/// Bounded admission from the microphone, followed by one ordered writer.
/// Closing admission is synchronous; draining waits for every accepted write.
final class GraniteAudioCapture: @unchecked Sendable {
    /// Admission transfers a copied microphone buffer to the sole consumer.
    /// The producer must not mutate the buffer after enqueueing it.
    struct PCM: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
    struct Outcome: Sendable {
        let issue: String?
        let requestStartedAt: TimeInterval?
    }

    private final class Admission: @unchecked Sendable {
        let lock = NSLock()
        let continuation: AsyncStream<PCM>.Continuation
        let maxQueuedFrames: Int
        var accepting = true
        var queuedFrames = 0
        var issue: String?
        var requestStartedAt: TimeInterval?

        init(continuation: AsyncStream<PCM>.Continuation, maxQueuedFrames: Int) {
            self.continuation = continuation
            self.maxQueuedFrames = max(0, maxQueuedFrames)
        }

        func enqueue(_ buffer: AVAudioPCMBuffer, capturedAt: TimeInterval) -> Bool {
            lock.withLock {
                guard accepting else { return false }
                guard capturedAt.isFinite, capturedAt >= 0 else {
                    failLocked("Audio capture timestamp was invalid")
                    return false
                }
                let frames = Int(buffer.frameLength)
                guard frames > 0 else { return true }
                guard frames <= maxQueuedFrames - queuedFrames else {
                    failLocked("Audio input queue overrun; recording is incomplete")
                    return false
                }
                if requestStartedAt == nil { requestStartedAt = capturedAt }
                queuedFrames += frames
                continuation.yield(PCM(buffer: buffer))
                return true
            }
        }

        func close() { lock.withLock { accepting = false; continuation.finish() } }
        func fail(_ message: String) { lock.withLock { failLocked(message) } }
        private func failLocked(_ message: String) {
            if issue == nil { issue = message }
            accepting = false
            continuation.finish()
        }
        func complete(_ frames: Int) { lock.withLock { queuedFrames -= frames } }
        func outcome() -> Outcome {
            lock.withLock { Outcome(issue: issue, requestStartedAt: requestStartedAt) }
        }
    }

    private let admission: Admission
    private let worker: Task<Void, Never>

    init(maxQueuedFrames: Int,
         onBuffer: @escaping @Sendable (PCM) async throws -> Void) {
        let pair = AsyncStream<PCM>.makeStream()
        let admission = Admission(continuation: pair.continuation, maxQueuedFrames: maxQueuedFrames)
        self.admission = admission
        worker = Task {
            for await pcm in pair.stream {
                let buffer = pcm.buffer
                guard admission.outcome().issue == nil else { break }
                do { try await onBuffer(pcm) }
                catch {
                    admission.fail("Audio recording failed: \(error.localizedDescription)")
                    break
                }
                admission.complete(Int(buffer.frameLength))
            }
        }
    }

    @discardableResult
    func enqueue(_ buffer: AVAudioPCMBuffer, capturedAt: TimeInterval) -> Bool {
        admission.enqueue(buffer, capturedAt: capturedAt)
    }
    func fail(_ message: String) { admission.fail(message) }
    func closeAdmission() { admission.close() }
    func closeAndDrain() async -> Outcome {
        admission.close()
        await worker.value
        return admission.outcome()
    }
    deinit { admission.close() }
}
