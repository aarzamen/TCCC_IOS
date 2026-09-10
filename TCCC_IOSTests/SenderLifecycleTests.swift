import XCTest
@testable import TCCC_IOS

@MainActor
final class SenderLifecycleTests: XCTestCase {
    private actor DeferredRenderer {
        private var pending: [CheckedContinuation<SenderSynthesisResult, Error>] = []
        private var starts: [(Int, CheckedContinuation<Void, Never>)] = []
        private(set) var requests: [SenderSynthesisRequest] = []

        func synthesize(_ request: SenderSynthesisRequest) async throws -> SenderSynthesisResult {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(request)
                pending.append(continuation)
                let ready = starts.filter { requests.count >= $0.0 }
                starts.removeAll { requests.count >= $0.0 }
                for (_, waiter) in ready { waiter.resume() }
            }
        }

        func waitForRequests(_ count: Int) async {
            if requests.count >= count { return }
            await withCheckedContinuation { starts.append((count, $0)) }
        }

        func succeed(_ index: Int) {
            pending[index].resume(returning: SenderSynthesisResult(
                audioURL: URL(fileURLWithPath: "/tmp/sender-synthetic-missing-\(index).wav"),
                duration: 2, sentenceTimings: [], rendererName: "Fixture renderer"
            ))
        }

        func fail(_ index: Int) { pending[index].resume(throwing: FixtureFailure.expected) }
    }

    private enum FixtureFailure: Error { case expected }

    func testSliderAssignmentsStayBoundedWithoutRecursiveObservation() {
        let model = SenderViewModel()
        for _ in 0..<20 {
            model.speed = 1.1
            model.pitchSemitones = -0.5
            model.volume = 0.6
            XCTAssertEqual(model.speed, 1.1)
            XCTAssertEqual(model.pitchSemitones, -0.5)
            XCTAssertEqual(model.volume, 0.6)
        }
        for value in [-Double.infinity, -100, Double.nan] {
            model.speed = value
            model.pitchSemitones = value
            model.volume = value
            XCTAssertEqual(model.speed, 0.7)
            XCTAssertEqual(model.pitchSemitones, -2)
            XCTAssertEqual(model.volume, 0)
        }
        for value in [100, Double.infinity] {
            model.speed = value
            model.pitchSemitones = value
            model.volume = value
            XCTAssertEqual(model.speed, 1.3)
            XCTAssertEqual(model.pitchSemitones, 2)
            XCTAssertEqual(model.volume, 1)
        }
    }

    func testCancelledNonCooperativeRendererCannotPublishOrNavigate() async {
        let renderer = DeferredRenderer()
        let model = SenderViewModel(synthesizeHandler: { try await renderer.synthesize($0) })
        model.script = "Synthetic training scenario"
        let task = Task { await model.send() }
        await renderer.waitForRequests(1)
        var ambientStopped = false
        model.endSurfaceActivity { ambientStopped = true }
        XCTAssertTrue(ambientStopped)
        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.synthesisState, .idle)
        await renderer.succeed(0)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(model.readout)
        XCTAssertNil(model.errorMessage)
    }

    func testOldCompletionDoesNotClearNewRequestBusyState() async {
        let renderer = DeferredRenderer()
        let model = SenderViewModel(synthesizeHandler: { try await renderer.synthesize($0) })
        model.script = "First request"
        let first = Task { await model.send() }
        await renderer.waitForRequests(1)
        model.cancelSynthesis()
        model.script = "Second request"
        let second = Task { await model.send() }
        await renderer.waitForRequests(2)
        await renderer.fail(0)
        let obsolete = await first.value
        XCTAssertNil(obsolete)
        XCTAssertTrue(model.isSending)
        XCTAssertNil(model.errorMessage)
        await renderer.succeed(1)
        let current = await second.value
        XCTAssertEqual(current?.script, "Second request")
        XCTAssertFalse(model.isSending)
    }

    func testSuccessfulReadoutKeepsCapturedRequestSettings() async {
        let renderer = DeferredRenderer()
        let model = SenderViewModel(synthesizeHandler: { try await renderer.synthesize($0) })
        model.script = "Original script"
        model.selectedVoiceID = "af_heart"
        model.speed = 0.9
        model.pitchSemitones = -1
        model.volume = 0.4
        let task = Task { await model.send() }
        await renderer.waitForRequests(1)
        model.script = "Edited script"
        model.selectedVoiceID = "am_adam"
        model.speed = 1.3
        model.pitchSemitones = 2
        model.volume = 1
        await renderer.succeed(0)
        let result = await task.value
        XCTAssertEqual(result?.script, "Original script")
        XCTAssertEqual(result?.voiceID, "af_heart")
        XCTAssertEqual(result?.speed, 0.9)
        XCTAssertEqual(result?.pitchSemitones, -1)
        XCTAssertEqual(result?.volume, 0.4)
    }

    func testFailedReadoutAlsoKeepsCapturedRequestSettings() async {
        let renderer = DeferredRenderer()
        let model = SenderViewModel(synthesizeHandler: { try await renderer.synthesize($0) })
        model.script = "Original failure fixture"
        model.selectedVoiceID = "af_heart"
        let task = Task { await model.send() }
        await renderer.waitForRequests(1)
        model.script = "Different text"
        model.selectedVoiceID = "am_adam"
        await renderer.fail(0)
        let result = await task.value
        XCTAssertEqual(result?.script, "Original failure fixture")
        XCTAssertEqual(result?.voiceID, "af_heart")
        XCTAssertNotNil(result?.errorMessage)
    }

    func testLeavingAfterCompletionInvalidatesNavigationTicket() async {
        let model = SenderViewModel(synthesizeHandler: { _ in throw FixtureFailure.expected })
        model.script = "Navigation fixture"
        let result = await model.send()
        XCTAssertNotNil(result)
        model.endSurfaceActivity(stopAmbient: {})
        XCTAssertFalse(model.consumeReadoutNavigation(for: result!.id))
    }

    func testNavigationTicketCanOnlyBeConsumedOnce() async {
        let model = SenderViewModel(synthesizeHandler: { _ in throw FixtureFailure.expected })
        model.script = "Navigation fixture"
        let result = await model.send()
        XCTAssertNotNil(result)
        XCTAssertTrue(model.consumeReadoutNavigation(for: result!.id))
        XCTAssertFalse(model.consumeReadoutNavigation(for: result!.id))
    }

    func testCancellingCallerAlsoFencesNonCooperativeCompletion() async {
        let renderer = DeferredRenderer()
        let model = SenderViewModel(synthesizeHandler: { try await renderer.synthesize($0) })
        model.script = "Cancellation fixture"
        let task = Task { await model.send() }
        await renderer.waitForRequests(1)
        task.cancel()
        await renderer.succeed(0)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(model.readout)
        XCTAssertFalse(model.isSending)
        XCTAssertEqual(model.synthesisState, .idle)
    }
}
