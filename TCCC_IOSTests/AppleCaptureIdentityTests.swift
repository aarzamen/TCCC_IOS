import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class AppleCaptureIdentityTests: XCTestCase {
    private func update(_ text: String, request: UUID,
                        termination: CaptureTermination? = nil) -> RecognitionUpdate {
        RecognitionUpdate(text: text, isFinal: termination == .finalized, timestamp: Date(),
            requestID: request, termination: termination)
    }

    func testPartialsStayVisibleUntilFinalAndLateADoesNotReplaceB() async {
        let state = AppState()
        let generation = state.beginCapture()
        let a = UUID(), b = UUID()
        await state.receiveAppleCapture(update("heart rate 110", request: a), generation: generation)
        XCTAssertEqual(state.partialTranscript, "heart rate 110")
        XCTAssertNil(state.primaryPatient)
        await state.receiveAppleCapture(update("heart rate 110", request: a, termination: .finalized), generation: generation)
        await state.receiveAppleCapture(update("blood pressure 90 over 60", request: b), generation: generation)
        await state.receiveAppleCapture(update("heart rate 180", request: a, termination: .finalized), generation: generation)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 110)
        XCTAssertEqual(state.partialTranscript, "blood pressure 90 over 60")
        XCTAssertEqual(state.transcript.filter { $0.speaker == .medic }.count, 1)
    }

    func testDistinctIdenticalRequestsAreBothRetained() async {
        let state = AppState()
        let generation = state.beginCapture()
        for _ in 0..<2 {
            await state.receiveAppleCapture(update("airway patent", request: UUID(), termination: .finalized), generation: generation)
        }
        XCTAssertEqual(state.transcript.filter { $0.speaker == .medic }.count, 2)
        let log = await state.engine.snapshotLog()
        let snapshot = await state.engine.snapshot()
        let replay = PatientStateEngine.standard()
        await replay.restore(log)
        let restored = await replay.snapshot()
        XCTAssertEqual(snapshot, restored)
    }

    func testIncompleteTextIsDurableEvidenceWithoutClinicalFacts() async throws {
        let state = AppState()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        state.documentsURL = temp
        state.encounterStore = EncounterStore(baseURL: temp)
        try await state.encounterStore?.startNewCasualty(id: state.casualtyId,
            startUnix: Date().timeIntervalSince1970)
        let generation = state.beginCapture()
        await state.receiveAppleCapture(update("heart rate 180", request: UUID(), termination: .timedOut), generation: generation)
        XCTAssertNil(state.primaryPatient?.vitals.hr)
        let store = try XCTUnwrap(state.encounterStore)
        let restored = try await store.loadActiveEncounter()
        let log = try XCTUnwrap(restored?.1)
        XCTAssertTrue(log.events.contains { event in
            if case .asrSegment(let segment) = event {
                return !segment.isFinal && segment.text.contains("CAPTURE INCOMPLETE") && segment.text.contains("180")
            }
            return false
        })
        let replay = PatientStateEngine.standard()
        await replay.restore(log)
        let snapshot = await replay.snapshot()
        XCTAssertNil(snapshot["PATIENT_1"]?.vitals.hr)
    }

    func testOldCaptureCannotWriteIntoNewCasualty() async {
        let state = AppState()
        let old = state.beginCapture()
        await state.newPatient()
        await state.receiveAppleCapture(update("heart rate 180", request: UUID(), termination: .finalized), generation: old)
        XCTAssertNil(state.primaryPatient)
        XCTAssertFalse(state.transcript.contains { $0.text.contains("180") })
    }

    func testOperatorDecisionDuringRecognitionRequiresReview() async {
        let state = AppState()
        let generation = state.beginCapture(), request = UUID()
        await state.receiveAppleCapture(update("heart rate 180", request: request), generation: generation)
        await state.engine.recordOperatorRejectedFact(factId: nil, domain: "vitals", field: "hr",
            rawValue: "180", to: "PATIENT_1")
        await state.receiveAppleCapture(update("heart rate 180", request: request, termination: .finalized), generation: generation)
        XCTAssertTrue(state.transcript.contains { $0.text.contains("REVIEW REQUIRED") })
        let snapshot = await state.engine.snapshot()
        XCTAssertNil(snapshot["PATIENT_1"]?.vitals.hr)
    }

    func testDecisionBeforeFirstCallbackIsNotOverwritten() async {
        let state = AppState()
        let generation = state.beginCapture()
        let started = ProcessInfo.processInfo.systemUptime
        await state.engine.recordOperatorAcceptedFact(write: .heartRate(90), factId: nil,
            domain: "vitals", field: "hr", rawValue: "90", to: "PATIENT_1")
        var result = update("heart rate 180", request: UUID(), termination: .finalized)
        result.requestStartedAt = started
        await state.receiveAppleCapture(result, generation: generation)
        let snapshot = await state.engine.snapshot()
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals.hr, 90)
        XCTAssertTrue(state.transcript.contains { $0.text.contains("REVIEW REQUIRED") })
    }
}
