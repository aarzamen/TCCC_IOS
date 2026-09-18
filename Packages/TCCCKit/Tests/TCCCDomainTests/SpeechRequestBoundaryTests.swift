import XCTest
@testable import TCCCDomain

final class SpeechRequestBoundaryTests: XCTestCase {
    func testEightSecondWatchdogDoesNotCutNumberAcrossRequests() {
        var boundary = SpeechRequestBoundary(openedAt: 0)
        boundary.observeHypothesis("heart rate one", at: 7.8)
        boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: 7.9)
        boundary.requestRotation()
        XCTAssertEqual(boundary.decision(at: 8), .keepListening,
                       "The temporary 'one' must not become a separate finalized clinical value")
        boundary.observeHypothesis("heart rate 120", at: 8.4)
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1, capturedAt: 8.5 + Double(index) * 0.1)
        }
        XCTAssertEqual(boundary.decision(at: 11.5), .finalize)
    }
    func testStableHypothesisCannotRotateWhileAudioContinues() {
        var boundary = SpeechRequestBoundary(openedAt: 0)
        boundary.observeHypothesis("heart rate one", at: 1)
        boundary.requestRotation()
        for index in 0..<40 {
            boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: 1 + Double(index) * 0.1)
        }
        XCTAssertEqual(boundary.decision(at: 5), .keepListening,
                       "A recognizer stall is not an acoustic pause")
    }
    func testRecentHypothesisChangePreventsRotationDuringQuietAudio() {
        var boundary = quietPendingBoundary()
        boundary.observeHypothesis("heart rate 121", at: 3.9)
        XCTAssertEqual(boundary.decision(at: 4), .keepListening)
    }
    func testOldOrMissingPCMDoesNotProveCurrentSilence() {
        let stale = quietPendingBoundary()
        XCTAssertEqual(stale.decision(at: 8), .keepListening)
        var incomplete = SpeechRequestBoundary(openedAt: 0)
        incomplete.requestRotation()
        incomplete.observeAudio(rms: 0.001, duration: 0.1, capturedAt: 2)
        incomplete.observeAudio(rms: 0.001, duration: 0.1, capturedAt: 3.9)
        XCTAssertEqual(incomplete.decision(at: 4), .keepListening,
                       "Separated quiet buffers must not stand in for continuous silence")
    }
    func testRequestResetDoesNotCarryRotationPermissionForward() {
        var boundary = quietPendingBoundary()
        XCTAssertEqual(boundary.decision(at: 4), .finalize)
        boundary = SpeechRequestBoundary(openedAt: 4)
        boundary.observeHypothesis("blood pressure ninety", at: 4.1)
        boundary.observeAudio(rms: 0.04, duration: 0.1, capturedAt: 4.1)
        XCTAssertEqual(boundary.decision(at: 4.2), .keepListening)
    }
    func testContinuousSpeechLimitIsIncompleteInsteadOfForcedClinicalFinal() {
        var boundary = SpeechRequestBoundary(openedAt: 0)
        boundary.requestRotation()
        for index in 0..<560 {
            let start = Double(index) * 0.1
            boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: start)
            boundary.observeHypothesis("word \(index)", at: start)
        }
        XCTAssertEqual(boundary.decision(at: 56), .incomplete)
    }
    func testPreRollCountsTowardRequestAudioBudgetButCannotAuthorizeRotation() {
        var boundary = SpeechRequestBoundary(openedAt: 100)
        boundary.requestRotation()
        for index in 0..<550 {
            boundary.observeAudio(rms: 0.001, duration: 0.1, capturedAt: 40 + Double(index) * 0.1)
        }
        XCTAssertEqual(boundary.decision(at: 100), .incomplete)
    }
    func testInvalidAudioEvidenceCannotAuthorizeRotation() {
        for invalid in [Float.nan, .infinity, -.infinity, -1] {
            var boundary = quietPendingBoundary()
            boundary.observeAudio(rms: invalid, duration: 0.1, capturedAt: 4)
            XCTAssertEqual(boundary.decision(at: 4.1), .keepListening)
        }
    }

    func testCaptureTailDeadlineCannotUpgradeOngoingSpeechToSafeFinal() {
        var boundary = SpeechRequestBoundary(openedAt: 0)
        boundary.observeHypothesis("heart rate one", at: 29.8)
        boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: 29.9)
        boundary.requestRotation()
        XCTAssertNotEqual(boundary.decision(at: 30), .finalize,
                          "A fixed tail deadline must classify a cut fragment as review-only")
        boundary.observeHypothesis("heart rate 120", at: 30.2)
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1,
                                  capturedAt: 30.3 + Double(index) * 0.1)
        }
        XCTAssertEqual(boundary.decision(at: 33.3), .finalize)
    }

    private func quietPendingBoundary() -> SpeechRequestBoundary {
        var boundary = SpeechRequestBoundary(openedAt: 0)
        boundary.observeHypothesis("heart rate 120", at: 1)
        boundary.requestRotation()
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1, capturedAt: 1 + Double(index) * 0.1)
        }
        return boundary
    }
}
