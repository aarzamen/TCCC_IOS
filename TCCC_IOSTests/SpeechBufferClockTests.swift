import Foundation
import XCTest
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class SpeechBufferClockTests: XCTestCase {
    func testPreRollCapturedBeforeManualCorrectionRequiresReview() async {
        let capturedAt = ProcessInfo.processInfo.systemUptime
        let engine = PatientStateEngine.standard()
        await engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")
        let revision = await engine.operatorRevision()

        // Synthetic opening safely after the decision, with older pre-roll.
        var clock = SpeechBufferClock(openedAt: ProcessInfo.processInfo.systemUptime + 1)
        clock.includeBuffer(capturedAt: capturedAt)
        let accepted = await engine.processCaptureTranscript("heart rate 180",
            operatorRevision: revision, requestStartedAt: clock.requestStartedAt)

        XCTAssertFalse(accepted)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 90)
        let log = await engine.snapshotLog()
        XCTAssertTrue(log.events.contains { event in
            if case .asrSegment(let segment) = event {
                return !segment.isFinal && segment.text.contains("REVIEW REQUIRED")
            }
            return false
        })
    }

    func testSuccessorRetainsQueuedAudioTimeAcrossRequestRotation() async {
        let queuedAt = ProcessInfo.processInfo.systemUptime
        var clock = SpeechBufferClock(openedAt: queuedAt - 10)
        clock.includeBuffer(capturedAt: queuedAt - 5)
        let engine = PatientStateEngine.standard()
        await engine.recordOperatorAcceptedFact(write: .heartRate(72), factId: nil,
            domain: "vitals", field: "hr", rawValue: "72", to: "PATIENT_1")
        let revision = await engine.operatorRevision()

        // The earlier request finishes after the correction. Its successor must
        // use the queued frame's time, not the new request's opening time.
        let successorOpenedAt = ProcessInfo.processInfo.systemUptime + 1
        clock = SpeechBufferClock(openedAt: successorOpenedAt)
        clock.includeBuffer(capturedAt: queuedAt)
        clock.includeBuffer(capturedAt: successorOpenedAt + 0.1)
        XCTAssertEqual(clock.requestStartedAt, queuedAt)
        let accepted = await engine.processCaptureTranscript("heart rate 160",
            operatorRevision: revision, requestStartedAt: clock.requestStartedAt)
        XCTAssertFalse(accepted)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 72)
    }

    func testEmptyAndNewLiveRequestsKeepTheirOwnOpeningBoundary() async {
        let engine = PatientStateEngine.standard()
        await engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")
        let revision = await engine.operatorRevision()
        let openedAt = ProcessInfo.processInfo.systemUptime + 1
        var clock = SpeechBufferClock(openedAt: openedAt)
        XCTAssertEqual(clock.requestStartedAt, openedAt)
        clock.includeBuffer(capturedAt: openedAt + 0.1)
        XCTAssertEqual(clock.requestStartedAt, openedAt)

        // New speech after a prior manual decision remains eligible. The clock
        // must not carry a previous request's older audio boundary forward.
        let accepted = await engine.processCaptureTranscript("heart rate 95",
            operatorRevision: revision, requestStartedAt: clock.requestStartedAt)
        XCTAssertTrue(accepted)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 95)
    }

    func testDelayedLiveFrameMovesFenceBackBeforeAnyRecognitionUpdate() {
        var clock = SpeechBufferClock(openedAt: 100)
        clock.includeBuffer(capturedAt: 99)
        clock.includeBuffer(capturedAt: 98)
        clock.includeBuffer(capturedAt: 101)
        XCTAssertEqual(clock.requestStartedAt, 98)
    }

    func testUnknownBufferTimingCannotOverwriteManualCorrection() async {
        let engine = PatientStateEngine.standard()
        await engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")
        let revision = await engine.operatorRevision()
        for unknown in [TimeInterval.nan, .infinity, -.infinity, -1] {
            var clock = SpeechBufferClock(openedAt: ProcessInfo.processInfo.systemUptime + 1)
            clock.includeBuffer(capturedAt: unknown)
            clock.includeBuffer(capturedAt: ProcessInfo.processInfo.systemUptime + 2)
            XCTAssertEqual(clock.requestStartedAt, 0)
            let accepted = await engine.processCaptureTranscript("heart rate 180",
                operatorRevision: revision, requestStartedAt: clock.requestStartedAt)
            XCTAssertFalse(accepted)
        }
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 90)
    }

    func testUnknownOpeningTimeStaysConservativeAfterValidBuffers() {
        for unknown in [TimeInterval.nan, .infinity, -.infinity, -1] {
            var clock = SpeechBufferClock(openedAt: unknown)
            clock.includeBuffer(capturedAt: 100)
            XCTAssertEqual(clock.requestStartedAt, 0)
        }
    }
}
