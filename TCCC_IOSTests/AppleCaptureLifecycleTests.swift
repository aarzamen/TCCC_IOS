import XCTest
@testable import TCCC_IOS

final class AppleCaptureLifecycleTests: XCTestCase {
    func testUnsafeRequestBoundaryIsReviewOnlyAndCaptureContinues() {
        var state = CaptureRequestState()
        let first = state.requestID
        XCTAssertTrue(state.endRequest(requiresReview: true))
        XCTAssertTrue(state.requestRequiresReview)
        XCTAssertFalse(state.endRequest())
        XCTAssertTrue(state.requestRequiresReview,
                      "A second boundary request cannot upgrade a forced fragment to final")
        XCTAssertEqual(state.finalized(first, hasBufferedAudio: true), true)
        XCTAssertFalse(state.closed)
        XCTAssertNotEqual(state.requestID, first)
        XCTAssertTrue(state.requestRequiresReview,
                      "The beginning of the successor may be a severed negation or number")
        XCTAssertFalse(state.awaitingFinal)
        let second = state.requestID
        XCTAssertEqual(state.finalized(second, hasBufferedAudio: true), true)
        XCTAssertTrue(state.requestRequiresReview,
                      "A natural framework final does not prove the unsafe context ended")
        let third = state.requestID
        XCTAssertTrue(state.endRequest()) // caller verified quiet PCM + stable hypothesis
        XCTAssertTrue(state.requestRequiresReview)
        XCTAssertEqual(state.finalized(third, hasBufferedAudio: true), true)
        XCTAssertFalse(state.requestRequiresReview,
                       "Only the successor after a verified safe boundary is clinical again")
    }

    func testFinalizingQueuesAudioForExactlyOneSuccessor() {
        var state = CaptureRequestState()
        let first = state.requestID
        XCTAssertTrue(state.endRequest())
        XCTAssertFalse(state.endRequest())
        XCTAssertTrue(state.awaitingFinal)
        XCTAssertEqual(state.finalized(first, hasBufferedAudio: true), true)
        let second = state.requestID
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(state.awaitingFinal)
        XCTAssertNil(state.finalized(first, hasBufferedAudio: true))
        XCTAssertEqual(state.requestID, second)
    }

    func testUtteranceFinalDoesNotShortenCaptureTail() {
        var state = CaptureRequestState()
        XCTAssertEqual(state.finalized(state.requestID, hasBufferedAudio: false), true)
        XCTAssertFalse(state.closed)
        state.endTail()
        XCTAssertTrue(state.endRequest())
        XCTAssertEqual(state.finalized(state.requestID, hasBufferedAudio: false), false)
        XCTAssertTrue(state.closed)
    }

    func testTailExpiryDrainsAudioQueuedDuringEarlierFinalization() {
        var state = CaptureRequestState()
        _ = state.endRequest()
        state.endTail()
        XCTAssertEqual(state.finalized(state.requestID, hasBufferedAudio: true), true)
        XCTAssertTrue(state.endRequest())
        XCTAssertEqual(state.finalized(state.requestID, hasBufferedAudio: false), false)
    }

    func testAbortAndOldCaptureCallbacksCannotAffectNewCapture() {
        var old = CaptureRequestState()
        let oldID = old.requestID
        XCTAssertTrue(old.close())
        XCTAssertFalse(old.close())
        XCTAssertNil(old.finalized(oldID, hasBufferedAudio: true))
        var new = CaptureRequestState()
        XCTAssertNil(new.finalized(oldID, hasBufferedAudio: false))
        XCTAssertFalse(new.closed)
    }
}
