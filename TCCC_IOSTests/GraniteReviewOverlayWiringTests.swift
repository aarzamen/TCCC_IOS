// TCCC_IOSTests/GraniteReviewOverlayWiringTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteReviewOverlayWiringTests: XCTestCase {
    func testAcceptButtonActionAppliesThroughState() async {
        let state = AppState()
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "88", evidenceIds: ["seg-1"], confidence: .high)
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: []))
        state.graniteReviewQueue = [item]

        // The overlay's accept action is this closure (mirrors the button body).
        if let accepted = OperatorAcceptedFact(fact, from: item.validation) {
            await state.acceptGraniteFact(accepted, in: item)
        }
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)
    }
}
