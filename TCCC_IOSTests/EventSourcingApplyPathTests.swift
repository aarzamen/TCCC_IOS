// TCCC_IOSTests/EventSourcingApplyPathTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class EventSourcingApplyPathTests: XCTestCase {

    // Setup mirrors the existing GraniteApplyPathTests verbatim (AppState(),
    // GraniteValidationResult has NO isAccepted param — it's computed from errors).
    private func fact(_ field: String, _ value: String, domain: String = "vitals") -> GraniteCandidateFact {
        GraniteCandidateFact(id: "fact-1", patientId: "PATIENT_1", domain: domain,
                             field: field, value: value, evidenceIds: ["seg-1"], confidence: .medium)
    }
    private func validation(_ facts: [GraniteCandidateFact]) -> GraniteValidationResult {
        GraniteValidationResult(acceptedFacts: facts, conflicts: [], errors: [])
    }
    private func item(_ f: GraniteCandidateFact) -> GraniteReviewItem {
        GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: f.patientId,
                candidateFacts: [f], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([f]))
    }

    func testAcceptedFactStillMutatesEngine() async throws {
        let state = AppState()
        let f = fact("heartRate", "120")
        let it = item(f)
        state.graniteReviewQueue = [it]
        let accepted = OperatorAcceptedFact(f, from: it.validation)!
        await state.acceptGraniteFact(accepted, in: it)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
    }

    func testAcceptedFactAppendsOperatorAcceptedEvent() async throws {
        let state = AppState()
        let f = fact("heartRate", "120")
        let it = item(f)
        state.graniteReviewQueue = [it]
        let accepted = OperatorAcceptedFact(f, from: it.validation)!
        await state.acceptGraniteFact(accepted, in: it)
        let log = await state.engine.snapshotLog()
        XCTAssertTrue(log.events.contains {
            if case .operatorAcceptedFact(let p) = $0, p.field == "heartRate",
               let w = p.write, w == .heartRate(120) { return true }
            return false
        })
    }
}
