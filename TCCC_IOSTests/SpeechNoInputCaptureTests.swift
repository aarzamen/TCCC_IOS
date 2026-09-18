import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class SpeechNoInputCaptureTests: XCTestCase {
    func testQuietEmptySuccessorPreservesSpeechAndContinuesRemainingTail() async {
        let state = AppState()
        let generation = state.beginCapture()
        state.isRecording = true
        var capture = CaptureRequestState()
        let initial = capture.requestID
        await state.receiveAppleCapture(update("heart rate 120", capture: capture), generation: generation)
        XCTAssertEqual(capture.finalized(initial, hasBufferedAudio: true), true)
        let emptySuccessor = capture.requestID
        XCTAssertTrue(capture.endRequest())
        XCTAssertTrue(canCompleteQuietSuccessor(capture))

        await state.receiveAppleCapture(update("", capture: capture), generation: generation)
        XCTAssertEqual(capture.finalized(emptySuccessor, hasBufferedAudio: false), true)
        XCTAssertFalse(capture.closed)
        XCTAssertFalse(capture.tailExpired)
        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
        XCTAssertNil(state.recognitionError)
        XCTAssertEqual(state.transcript.filter { $0.speaker == .medic }.count, 1)

        // A quiet empty rotation must not shorten the 30-second capture tail;
        // speech arriving in the remaining tail is still assigned to this capture.
        await state.receiveAppleCapture(update("blood pressure 90 over 60", capture: capture),
                                        generation: generation)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.systolic, 90)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.diastolic, 60)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
        XCTAssertNil(state.recognitionError)
    }

    func testQuietEmptyTailCompletionClosesCaptureWithoutErasingExistingError() async {
        let state = AppState()
        let generation = state.beginCapture()
        var capture = CaptureRequestState()
        let initial = capture.requestID
        await state.receiveAppleCapture(update("heart rate 120", capture: capture), generation: generation)
        XCTAssertEqual(capture.finalized(initial, hasBufferedAudio: false), true)
        capture.endTail()
        XCTAssertTrue(capture.endRequest())
        XCTAssertTrue(canCompleteQuietSuccessor(capture))
        state.recognitionError = "Earlier audio save failure requires review"
        let emptySuccessor = capture.requestID

        await state.receiveAppleCapture(update("", capture: capture), generation: generation)
        XCTAssertEqual(capture.finalized(emptySuccessor, hasBufferedAudio: false), false)
        XCTAssertTrue(capture.closed)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
        XCTAssertEqual(state.recognitionError, "Earlier audio save failure requires review")
        XCTAssertEqual(state.transcript.filter { $0.speaker == .medic }.count, 1)
    }

    private func update(_ text: String, capture: CaptureRequestState) -> RecognitionUpdate {
        RecognitionUpdate(text: text, isFinal: true, timestamp: Date(),
            captureID: capture.captureID, requestID: capture.requestID, termination: .finalized)
    }

    private func canCompleteQuietSuccessor(_ capture: CaptureRequestState) -> Bool {
        var boundary = SpeechRequestBoundary(openedAt: 100)
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1,
                                  capturedAt: 100 + Double(index) * 0.1)
        }
        return boundary.canCompleteEmptySuccessor(errorDomain: "kAFAssistantErrorDomain",
            errorCode: 1110, text: "", hadFinalizedSpeech: true,
            wasDeliberatelyEnded: capture.awaitingFinal, requiresReview: capture.requestRequiresReview)
    }
}
