import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class SpeechRequestBoundaryIntegrationTests: XCTestCase {
    func testDeferredBoundaryExtractsWholeHypothesisAfterThePause() async {
        let state = AppState()
        let generation = state.beginCapture()
        let request = UUID()
        var boundary = SpeechRequestBoundary(openedAt: 0)
        var assembler = SpeechUtteranceAssembler()
        assembler.ingest(text: "heart rate one")
        boundary.observeHypothesis(assembler.transcript, at: 7.8)
        boundary.observeAudio(rms: 0.03, duration: 0.1, capturedAt: 7.9)
        boundary.requestRotation()
        XCTAssertEqual(boundary.decision(at: 8), .keepListening)
        await state.receiveAppleCapture(RecognitionUpdate(text: assembler.transcript,
            isFinal: false, timestamp: Date(), requestID: request), generation: generation)
        XCTAssertNil(state.primaryPatient?.vitals.hr)

        // Same request's revision completes the number. No cross-request text
        // concatenation and no guessed correction from 1 + 20 to 120 occur.
        assembler.ingest(text: "heart rate 120 blood pressure 90 over 60 respiratory rate 22 oxygen saturation 96 percent")
        boundary.observeHypothesis(assembler.transcript, at: 8.4)
        for index in 0..<30 {
            boundary.observeAudio(rms: 0.001, duration: 0.1,
                                  capturedAt: 8.5 + Double(index) * 0.1)
        }
        XCTAssertEqual(boundary.decision(at: 11.5), .finalize)
        await state.receiveAppleCapture(RecognitionUpdate(text: assembler.transcript,
            isFinal: true, timestamp: Date(), requestID: request, termination: .finalized),
            generation: generation)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.systolic, 90)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.diastolic, 60)
        XCTAssertEqual(state.primaryPatient?.vitals.rr, 22)
        XCTAssertEqual(state.primaryPatient?.vitals.spo2, 96)
    }

    func testForcedFragmentStaysReviewOnlyWhileNextRequestRecords() async {
        let state = AppState()
        let generation = state.beginCapture()
        state.isRecording = true
        var capture = CaptureRequestState()
        let cutRequest = capture.requestID
        XCTAssertTrue(capture.endRequest(requiresReview: true))
        await state.receiveAppleCapture(RecognitionUpdate(text: "heart rate one",
            isFinal: false, timestamp: Date(), captureID: capture.captureID,
            requestID: cutRequest, termination: .failed,
            issue: "Speech crossed a recognition boundary without a pause"), generation: generation)
        XCTAssertNil(state.primaryPatient?.vitals.hr)
        XCTAssertTrue(state.transcript.contains { $0.text.contains("CAPTURE INCOMPLETE") && $0.text.contains("heart rate one") })
        XCTAssertTrue(state.isRecording)

        XCTAssertEqual(capture.finalized(cutRequest, hasBufferedAudio: true), true)
        XCTAssertTrue(capture.requestRequiresReview)
        await state.receiveAppleCapture(RecognitionUpdate(text: "20 blood pressure 90 over 60",
            isFinal: false, timestamp: Date(), captureID: capture.captureID,
            requestID: capture.requestID, termination: .failed), generation: generation)
        XCTAssertTrue(state.isRecording)
        XCTAssertNil(state.primaryPatient?.vitals.hr,
                     "Separate request fragments must not be guessed into a heart rate")
        XCTAssertNil(state.primaryPatient?.vitals.bp,
                     "The successor remains review-only until a verified safe boundary")
        XCTAssertTrue(capture.endRequest()) // verified quiet and stable at this boundary
        XCTAssertEqual(capture.finalized(capture.requestID, hasBufferedAudio: true), true)
        XCTAssertFalse(capture.requestRequiresReview)
        await state.receiveAppleCapture(RecognitionUpdate(text: "heart rate 120 blood pressure 90 over 60",
            isFinal: true, timestamp: Date(), captureID: capture.captureID,
            requestID: capture.requestID, termination: .finalized), generation: generation)
        XCTAssertTrue(state.isRecording)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.systolic, 90)
        XCTAssertEqual(state.primaryPatient?.vitals.bp?.diastolic, 60)
    }
}
