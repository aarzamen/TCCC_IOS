import XCTest
@testable import TCCC_IOS

final class ParakeetAudioProcessorTests: XCTestCase {
    private final class Observations: @unchecked Sendable {
        private let lock = NSLock()
        private var updates: [RecognitionUpdate] = []
        private var finishes = 0
        func append(_ update: RecognitionUpdate) { lock.withLock { updates.append(update) } }
        func finish() { lock.withLock { finishes += 1 } }
        var all: [RecognitionUpdate] { lock.withLock { updates } }
        var finishCount: Int { lock.withLock { finishes } }
    }

    private actor Decoder: ParakeetDecoding {
        enum Failure: Error { case synthetic }
        var calls: [String] = []
        var frames: [Float] = []
        var cumulative = ""
        var active = false
        var overlap = false
        var processCount = 0
        let suspendAt: Int?
        let failAt: Int?
        let eouAt: Set<Int>
        let repeatedText: String?
        var gate: CheckedContinuation<Void, Never>?
        var enteredWaiters: [CheckedContinuation<Void, Never>] = []

        init(suspendAt: Int? = nil, failAt: Int? = nil, eouAt: Set<Int> = [],
             repeatedText: String? = nil) {
            self.suspendAt = suspendAt
            self.failAt = failAt
            self.eouAt = eouAt
            self.repeatedText = repeatedText
        }

        func process(_ samples: [Float]) async throws -> ParakeetDecodeResult {
            if active { overlap = true }
            active = true
            processCount += 1
            let index = processCount
            calls.append("process\(index)")
            frames += samples
            if suspendAt == index {
                await withCheckedContinuation { continuation in
                    gate = continuation
                    enteredWaiters.forEach { $0.resume() }
                    enteredWaiters.removeAll()
                }
            }
            defer { active = false }
            if failAt == index { throw Failure.synthetic }
            let next = repeatedText ?? "word\(index)"
            cumulative += cumulative.isEmpty ? next : " " + next
            return ParakeetDecodeResult(text: cumulative, endOfUtterance: eouAt.contains(index))
        }

        func finish() async throws -> String {
            if active { overlap = true }
            calls.append("finish")
            return cumulative
        }

        func reset() async {
            if active { overlap = true }
            calls.append("reset")
            cumulative = ""
        }

        func waitForSuspension() async {
            if gate != nil { return }
            await withCheckedContinuation { enteredWaiters.append($0) }
        }

        func release() { gate?.resume(); gate = nil }
        func snapshot() -> (calls: [String], frames: [Float], overlap: Bool) { (calls, frames, overlap) }
    }

    private func processor(_ decoder: Decoder, _ observed: Observations,
                           captureID: UUID = UUID(), maxQueuedFrames: Int = 1_440_000) -> ParakeetAudioProcessor {
        ParakeetAudioProcessor(decoder: decoder, captureID: captureID,
            maxQueuedFrames: maxQueuedFrames,
            onUpdate: { observed.append($0) }, onFinish: { observed.finish() })
    }

    func testDecodesEveryBufferBeyondFirst160MillisecondsAndDrainsOnce() async {
        let decoder = Decoder()
        let observed = Observations()
        let capture = UUID()
        let subject = processor(decoder, observed, captureID: capture)
        for index in 1...5 {
            XCTAssertTrue(subject.enqueue(Array(repeating: Float(index), count: 2_560),
                                          capturedAt: Double(index)))
        }
        async let first: Void = subject.closeAndDrain()
        async let second: Void = subject.closeAndDrain()
        _ = await (first, second)
        let snapshot = await decoder.snapshot()
        XCTAssertEqual(snapshot.frames.count, 12_800)
        XCTAssertEqual(snapshot.frames, (1...5).flatMap { Array(repeating: Float($0), count: 2_560) })
        XCTAssertEqual(snapshot.calls, ["process1", "process2", "process3", "process4", "process5", "finish", "reset"])
        XCTAssertFalse(snapshot.overlap)
        XCTAssertEqual(observed.all.last?.text, "word1 word2 word3 word4 word5")
        XCTAssertEqual(observed.all.last?.termination, .finalized)
        XCTAssertTrue(observed.all.allSatisfy { $0.captureID == capture && $0.requestStartedAt == 1 })
        XCTAssertEqual(Set(observed.all.compactMap(\.requestID)).count, 1)
        XCTAssertEqual(observed.finishCount, 1)
        XCTAssertFalse(subject.enqueue([9], capturedAt: 9))
    }

    func testBoundaryAndCloseCannotOvertakeSuspendedInference() async {
        let decoder = Decoder(suspendAt: 1)
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.enqueue([1], capturedAt: 11)
        await decoder.waitForSuspension()
        subject.requestBoundary()
        subject.enqueue([2, 3], capturedAt: 22)
        let closing = Task { await subject.closeAndDrain() }
        let suspended = await decoder.snapshot()
        XCTAssertEqual(suspended.calls, ["process1"])
        await decoder.release()
        await closing.value
        let snapshot = await decoder.snapshot()
        XCTAssertEqual(snapshot.calls, ["process1", "finish", "reset", "process2", "finish", "reset"])
        XCTAssertFalse(snapshot.overlap)
        let finals = observed.all.filter { $0.isFinal }
        XCTAssertEqual(finals.map(\.text), ["word1", "word2"])
        XCTAssertEqual(finals.compactMap(\.requestStartedAt), [11, 22])
        XCTAssertNotEqual(finals[0].requestID, finals[1].requestID)
    }

    func testEOUThenEmptyBoundaryAndStopDoNotDuplicateFinal() async {
        let decoder = Decoder(eouAt: [2])
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.requestBoundary()
        subject.enqueue([1], capturedAt: 10)
        subject.enqueue([2], capturedAt: 20)
        subject.requestBoundary()
        subject.requestBoundary()
        await subject.closeAndDrain()
        let snapshot = await decoder.snapshot()
        XCTAssertEqual(snapshot.calls, ["process1", "process2", "finish", "reset"])
        XCTAssertEqual(observed.all.filter(\.isFinal).map(\.text), ["word1 word2"])
        XCTAssertEqual(observed.finishCount, 1)
    }

    func testRepeatedUtterancesRemainDistinctAcrossEOUBoundaries() async {
        let decoder = Decoder(eouAt: [1, 2], repeatedText: "tourniquet applied")
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.enqueue([1], capturedAt: 10)
        subject.enqueue([2], capturedAt: 20)
        await subject.closeAndDrain()
        let finals = observed.all.filter(\.isFinal)
        XCTAssertEqual(finals.map(\.text), ["tourniquet applied", "tourniquet applied"])
        XCTAssertEqual(Set(finals.compactMap(\.requestID)).count, 2)
        XCTAssertEqual(finals.compactMap(\.requestStartedAt), [10, 20])
    }

    func testDecoderFailureRetainsPartialAndDiscardsRemainingQueue() async {
        let decoder = Decoder(failAt: 2)
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.enqueue([1], capturedAt: 10)
        subject.enqueue([2], capturedAt: 20)
        subject.enqueue([3], capturedAt: 30)
        await subject.closeAndDrain()
        let snapshot = await decoder.snapshot()
        XCTAssertEqual(snapshot.calls, ["process1", "process2", "reset"])
        XCTAssertEqual(observed.all.last?.text, "word1")
        XCTAssertEqual(observed.all.last?.termination, .failed)
        XCTAssertNotNil(observed.all.last?.issue)
        XCTAssertFalse(observed.all.contains { $0.termination == .finalized })
        XCTAssertEqual(observed.finishCount, 1)
        XCTAssertFalse(subject.enqueue([4], capturedAt: 40))
    }

    func testOverloadCountsActiveFramesAndCannotFinalizeSuspendedEOU() async {
        let decoder = Decoder(suspendAt: 1, eouAt: [1])
        let observed = Observations()
        let subject = processor(decoder, observed, maxQueuedFrames: 3)
        XCTAssertTrue(subject.enqueue([1, 2], capturedAt: 10))
        await decoder.waitForSuspension()
        XCTAssertTrue(subject.enqueue([3], capturedAt: 20))
        XCTAssertFalse(subject.enqueue([4], capturedAt: 30))
        await decoder.release()
        await subject.closeAndDrain()
        let snapshot = await decoder.snapshot()
        XCTAssertEqual(snapshot.calls, ["process1", "reset"])
        XCTAssertEqual(observed.all.last?.text, "word1")
        XCTAssertEqual(observed.all.last?.termination, .failed)
        XCTAssertTrue(observed.all.last?.issue?.contains("capture limit") == true)
        XCTAssertFalse(observed.all.contains { $0.termination == .finalized })
        XCTAssertEqual(observed.finishCount, 1)
    }

    func testIngressFailureRetainsInFlightHypothesisAndEndsOnce() async {
        let decoder = Decoder(suspendAt: 1)
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.enqueue([1], capturedAt: 7)
        await decoder.waitForSuspension()
        subject.fail("Microphone queue overrun")
        subject.fail("Second failure must not replace the first")
        XCTAssertFalse(subject.enqueue([2], capturedAt: 8))
        await decoder.release()
        await subject.closeAndDrain()
        XCTAssertEqual(observed.all.last?.text, "word1")
        XCTAssertEqual(observed.all.last?.issue, "Microphone queue overrun")
        XCTAssertEqual(observed.all.last?.termination, .failed)
        XCTAssertEqual(observed.finishCount, 1)
    }
    @MainActor
    func testDelayedRecognitionCannotOverwriteDecisionAfterAudioAcquisition() async {
        let state = AppState()
        let generation = state.beginCapture()
        let decoder = Decoder(suspendAt: 1, repeatedText: "heart rate 180")
        let observed = Observations()
        let subject = processor(decoder, observed)
        subject.enqueue([1], capturedAt: ProcessInfo.processInfo.systemUptime)
        await decoder.waitForSuspension()
        await state.engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")
        await decoder.release()
        await subject.closeAndDrain()
        for update in observed.all {
            await state.receiveAppleCapture(update, generation: generation)
        }
        let snapshot = await state.engine.snapshot()
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals.hr, 90)
        XCTAssertTrue(state.transcript.contains { $0.text.contains("REVIEW REQUIRED") })
    }

}
