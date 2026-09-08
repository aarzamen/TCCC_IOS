import Foundation

struct ParakeetDecodeResult: Sendable {
    let text: String
    let endOfUtterance: Bool
}

protocol ParakeetDecoding: Sendable {
    func process(_ samples: [Float]) async throws -> ParakeetDecodeResult
    func finish() async throws -> String
    func reset() async
}

/// One consumer owns the decoder for the entire capture. In particular, a
/// boundary cannot reenter a suspended inference or overtake admitted audio.
final class ParakeetAudioProcessor: @unchecked Sendable {
    private enum Command: Sendable {
        case audio([Float], TimeInterval)
        case boundary
    }

    private final class Admission: @unchecked Sendable {
        let lock = NSLock()
        let continuation: AsyncStream<Command>.Continuation
        let maxQueuedFrames: Int
        private var accepting = true
        private var queuedFrames = 0
        private var failure: String?

        init(continuation: AsyncStream<Command>.Continuation, maxQueuedFrames: Int) {
            self.continuation = continuation
            self.maxQueuedFrames = max(0, maxQueuedFrames)
        }

        func enqueue(_ samples: [Float], at time: TimeInterval) -> Bool {
            lock.withLock {
                guard accepting else { return false }
                guard !samples.isEmpty else { return true }
                guard samples.count <= maxQueuedFrames - queuedFrames else {
                    failure = "Parakeet audio processing fell behind; queued audio exceeds the capture limit."
                    accepting = false
                    continuation.finish()
                    return false
                }
                queuedFrames += samples.count
                continuation.yield(.audio(samples, time))
                return true
            }
        }

        func boundary() {
            lock.withLock {
                if accepting { continuation.yield(.boundary) }
            }
        }

        func close() {
            lock.withLock {
                accepting = false
                continuation.finish()
            }
        }

        func fail(_ reason: String) {
            lock.withLock {
                guard accepting else { return }
                failure = reason
                accepting = false
                continuation.finish()
            }
        }

        func complete(_ frames: Int) {
            lock.withLock { queuedFrames -= frames }
        }

        func failureReason() -> String? { lock.withLock { failure } }
    }

    private final class Consumer: @unchecked Sendable {
        let decoder: any ParakeetDecoding
        let admission: Admission
        let captureID: UUID
        let onUpdate: @Sendable (RecognitionUpdate) -> Void
        let onFinish: @Sendable () -> Void
        var requestID = UUID()
        var requestStartedAt: TimeInterval?
        var retained = ""

        init(decoder: any ParakeetDecoding, admission: Admission, captureID: UUID,
             onUpdate: @escaping @Sendable (RecognitionUpdate) -> Void,
             onFinish: @escaping @Sendable () -> Void) {
            self.decoder = decoder
            self.admission = admission
            self.captureID = captureID
            self.onUpdate = onUpdate
            self.onFinish = onFinish
        }

        func update(final: Bool, termination: CaptureTermination? = nil, issue: String? = nil) {
            onUpdate(RecognitionUpdate(text: retained, isFinal: final, timestamp: Date(),
                captureID: captureID, requestID: requestID, termination: termination,
                issue: issue, requestStartedAt: requestStartedAt))
        }

        func checkAdmission() throws {
            if let reason = admission.failureReason() { throw ProcessingFailure(reason: reason) }
        }

        func finishSegment() async throws {
            guard requestStartedAt != nil else { return }
            try checkAdmission()
            let final = try await decoder.finish()
            try checkAdmission()
            // An empty terminal decoder result must not erase a delivered partial.
            if !final.isEmpty { retained = final }
            update(final: true, termination: .finalized)
            await decoder.reset()
            retained = ""
            requestStartedAt = nil
            requestID = UUID()
        }

        func run(_ stream: AsyncStream<Command>) async {
            defer { onFinish() }
            do {
                for await command in stream {
                    switch command {
                    case .audio(let samples, let capturedAt):
                        if requestStartedAt == nil { requestStartedAt = capturedAt }
                        try checkAdmission()
                        let result = try await decoder.process(samples)
                        admission.complete(samples.count)
                        if !result.text.isEmpty { retained = result.text }
                        // Overload can be reported while inference is suspended.
                        // Keep its newest hypothesis, but never finalize that segment.
                        try checkAdmission()
                        update(final: false)
                        if result.endOfUtterance { try await finishSegment() }
                    case .boundary:
                        try checkAdmission()
                        try await finishSegment()
                    }
                }
                try checkAdmission()
                try await finishSegment()
            } catch {
                admission.close()
                update(final: true, termination: .failed, issue: error.localizedDescription)
                await decoder.reset()
            }
        }
    }

    private struct ProcessingFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    private let admission: Admission
    private let worker: Task<Void, Never>

    init(decoder: any ParakeetDecoding, captureID: UUID = UUID(),
         maxQueuedFrames: Int = 1_440_000,
         onUpdate: @escaping @Sendable (RecognitionUpdate) -> Void,
         onFinish: @escaping @Sendable () -> Void) {
        let pair = AsyncStream<Command>.makeStream()
        let admission = Admission(continuation: pair.continuation, maxQueuedFrames: maxQueuedFrames)
        self.admission = admission
        let consumer = Consumer(decoder: decoder, admission: admission, captureID: captureID,
                                onUpdate: onUpdate, onFinish: onFinish)
        worker = Task { await consumer.run(pair.stream) }
    }

    @discardableResult
    func enqueue(_ samples: [Float], capturedAt: TimeInterval) -> Bool {
        admission.enqueue(samples, at: capturedAt)
    }

    func requestBoundary() { admission.boundary() }

    func fail(_ reason: String) { admission.fail(reason) }

    func closeAndDrain() async {
        admission.close()
        await worker.value
    }

    deinit { admission.close() }
}
