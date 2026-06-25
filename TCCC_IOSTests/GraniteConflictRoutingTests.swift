// TCCC_IOSTests/GraniteConflictRoutingTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteConflictRoutingTests: XCTestCase {
    func testContradictingFactRoutesToConflictNotAccept() async {
        let state = AppState()
        // Engine already holds hr = 88 (deterministic ground truth).
        await state.engine.apply([.heartRate(88)], to: "PATIENT_1")
        await state.refreshPatientSnapshot()

        // Model proposes a contradicting value.
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "120", evidenceIds: ["seg-1"], confidence: .medium)
        let validation = GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: [])
        let accepted = OperatorAcceptedFact(fact, from: validation)!

        await state.acceptGraniteFact(accepted, in:
            GraniteReviewItem(id: UUID(), createdAt: Date(),
                patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                    candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                    rejectedInputs: [], modelSelfCheck: "ok"),
                validation: validation))

        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)        // engine value HOLDS (④ resting state)
        XCTAssertNotNil(state.lastConflictMessage)                 // surfaced, operator-visible
        XCTAssertTrue(state.lastConflictMessage?.contains("120") ?? false)
        XCTAssertTrue(state.lastConflictMessage?.contains("88") ?? false)
    }

    func testAgreeingFactStillApplies() async {
        let state = AppState()
        await state.engine.apply([.heartRate(88)], to: "PATIENT_1")
        await state.refreshPatientSnapshot()
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "88", evidenceIds: ["seg-1"], confidence: .high)
        let validation = GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: [])
        await state.acceptGraniteFact(OperatorAcceptedFact(fact, from: validation)!, in:
            GraniteReviewItem(id: UUID(), createdAt: Date(),
                patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                    candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                    rejectedInputs: [], modelSelfCheck: "ok"),
                validation: validation))
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)        // no spurious conflict
        XCTAssertNil(state.lastConflictMessage)
    }
}
