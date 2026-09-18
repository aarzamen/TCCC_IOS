import XCTest
@testable import TCCCDomain

final class SpeechNoInputCompletionTests: XCTestCase {
    func testKnownNoSpeechAfterQuietEndedSuccessorCompletesWithoutFailure() {
        let boundary = quietRequest()
        XCTAssertTrue(canComplete(boundary))
    }

    func testQuietRoomNoiseDoesNotMakeEmptyTailAnError() {
        var boundary = SpeechRequestBoundary(openedAt: 100)
        for index in 0..<20 {
            boundary.observeAudio(rms: 0.004, duration: 0.1,
                                  capturedAt: 100 + Double(index) * 0.1)
        }
        XCTAssertTrue(canComplete(boundary))
    }

    func testInitialNoSpeechFailureIsNotSuppressed() {
        XCTAssertFalse(canComplete(quietRequest(), hadFinalizedSpeech: false))
    }

    func testUnexpectedErrorAndOtherDomainsAreNotSuppressed() {
        for code in [203, 1100, 1101, 1107, 1700] {
            XCTAssertFalse(canComplete(quietRequest(), errorCode: code))
        }
        XCTAssertFalse(canComplete(quietRequest(), errorDomain: "kLSRErrorDomain"))
        XCTAssertFalse(canComplete(quietRequest(), errorDomain: nil, errorCode: nil))
    }

    func testAnyRetainedPartialMakesNoSpeechFailureIncomplete() {
        XCTAssertFalse(canComplete(quietRequest(), text: "heart rate one"))
    }

    func testUnsafeBoundaryAndUnexpectedTerminationAreNotSuppressed() {
        XCTAssertFalse(canComplete(quietRequest(), requiresReview: true))
        XCTAssertFalse(canComplete(quietRequest(), wasDeliberatelyEnded: false))
    }

    func testQuietEndingDoesNotEraseEarlierUnrecognizedAudioActivity() {
        var boundary = SpeechRequestBoundary(openedAt: 100)
        boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: 100)
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1,
                                  capturedAt: 100.1 + Double(index) * 0.1)
        }
        XCTAssertFalse(canComplete(boundary),
                       "Unrecognized audible input must remain an error even without a text hypothesis")
    }

    func testMissingOrInvalidAudioCannotClaimBenignSilence() {
        XCTAssertFalse(canComplete(SpeechRequestBoundary(openedAt: 100)))
        for invalid in [Float.nan, .infinity, -.infinity, -1] {
            var boundary = quietRequest()
            boundary.observeAudio(rms: invalid, duration: 0.1, capturedAt: 102)
            XCTAssertFalse(canComplete(boundary))
        }
        var boundary = quietRequest()
        boundary.observeAudio(rms: 0, duration: 0, capturedAt: 102)
        XCTAssertFalse(canComplete(boundary))
    }

    private func quietRequest() -> SpeechRequestBoundary {
        var boundary = SpeechRequestBoundary(openedAt: 100)
        for index in 0..<20 {
            boundary.observeAudio(rms: 0.001, duration: 0.1,
                                  capturedAt: 100 + Double(index) * 0.1)
        }
        return boundary
    }

    private func canComplete(
        _ boundary: SpeechRequestBoundary,
        errorDomain: String? = "kAFAssistantErrorDomain", errorCode: Int? = 1110,
        text: String = "", hadFinalizedSpeech: Bool = true,
        wasDeliberatelyEnded: Bool = true, requiresReview: Bool = false
    ) -> Bool {
        boundary.canCompleteEmptySuccessor(errorDomain: errorDomain, errorCode: errorCode,
            text: text, hadFinalizedSpeech: hadFinalizedSpeech,
            wasDeliberatelyEnded: wasDeliberatelyEnded, requiresReview: requiresReview)
    }
}
