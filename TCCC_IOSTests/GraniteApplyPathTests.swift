// TCCC_IOSTests/GraniteApplyPathTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteApplyPathTests: XCTestCase {
    private func acceptedFact(_ field: String, _ value: String, domain: String = "vitals") -> GraniteCandidateFact {
        GraniteCandidateFact(id: "fact-1", patientId: "PATIENT_1", domain: domain,
                             field: field, value: value, evidenceIds: ["seg-1"], confidence: .medium)
    }
    private func validation(_ facts: [GraniteCandidateFact]) -> GraniteValidationResult {
        GraniteValidationResult(acceptedFacts: facts, conflicts: [], errors: [])
    }

    func testOperatorAcceptedFactRejectsNonAcceptedFact() {
        let fact = acceptedFact("heartRate", "88")
        XCTAssertNil(OperatorAcceptedFact(fact, from: validation([])))          // not in acceptedFacts → nil
        XCTAssertNotNil(OperatorAcceptedFact(fact, from: validation([fact])))   // in acceptedFacts → wraps
    }

    func testAcceptMutatesStateThroughEngine() async {
        let state = AppState()
        let fact = acceptedFact("heartRate", "88")
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([fact]))
        state.graniteReviewQueue = [item]
        let accepted = OperatorAcceptedFact(fact, from: item.validation)!

        await state.acceptGraniteFact(accepted, in: item)

        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)   // mutated through the engine
    }

    func testRejectDoesNotMutateAndClearsItem() async {
        let state = AppState()
        let fact = acceptedFact("heartRate", "88")
        let before = state.primaryPatient
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([fact]))
        state.graniteReviewQueue = [item]

        state.rejectGraniteReviewItem(item)

        XCTAssertEqual(state.primaryPatient, before)          // no mutation
        XCTAssertTrue(state.graniteReviewQueue.isEmpty)       // item cleared
    }
}
