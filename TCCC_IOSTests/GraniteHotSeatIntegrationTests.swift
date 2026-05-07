import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteHotSeatIntegrationTests: XCTestCase {
    func testInvalidPatchIsHeldForReviewWithoutMutatingState() {
        let state = AppState()
        let before = state.primaryPatient
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "march",
                    field: "hemorrhageIntervention",
                    value: "tourniquet",
                    evidenceIds: [],
                    confidence: .high
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        state.applyGraniteCandidatePatchForReview(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"],
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(state.primaryPatient, before)
        XCTAssertEqual(state.graniteReviewQueue.count, 1)
        XCTAssertEqual(state.graniteReviewQueue[0].status, .heldForValidation)
        XCTAssertFalse(state.graniteReviewQueue[0].validation.isAccepted)
        XCTAssertTrue(state.transcript.last?.text.contains("GRANITE REVIEW HELD") ?? false)
    }

    func testValidPatchIsQueuedForOperatorReviewWithoutMutatingState() {
        let state = AppState()
        let before = state.primaryPatient
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: "88",
                    evidenceIds: ["seg-1"],
                    confidence: .medium
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        state.applyGraniteCandidatePatchForReview(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"],
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(state.primaryPatient, before)
        XCTAssertEqual(state.graniteReviewQueue.count, 1)
        XCTAssertEqual(state.graniteReviewQueue[0].status, .readyForOperatorReview)
        XCTAssertTrue(state.graniteReviewQueue[0].validation.isAccepted)
        XCTAssertTrue(state.transcript.last?.text.contains("GRANITE REVIEW READY") ?? false)
    }

    func testLifecycleActionsClearGraniteReviewQueue() {
        let state = AppState()
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        state.applyGraniteCandidatePatchForReview(
            patch,
            knownEvidenceIds: [],
            knownPatientIds: ["PATIENT_1"],
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(state.graniteReviewQueue.count, 1)

        state.newPatient()
        XCTAssertTrue(state.graniteReviewQueue.isEmpty)

        state.applyGraniteCandidatePatchForReview(
            patch,
            knownEvidenceIds: [],
            knownPatientIds: ["PATIENT_1"],
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(state.graniteReviewQueue.count, 1)

        state.wipeSession()
        XCTAssertTrue(state.graniteReviewQueue.isEmpty)
    }
}
