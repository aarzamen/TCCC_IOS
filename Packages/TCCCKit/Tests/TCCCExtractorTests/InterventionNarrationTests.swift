import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class InterventionNarrationTests: XCTestCase {
    private func state(_ text: String) async -> PatientState {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(text, timestamp: Date(timeIntervalSince1970: 1000))
        return await engine.snapshot()["PATIENT_1"]!
    }

    func testExplicitTranexamicAcidAdministration() async {
        let patient = await state("Giving one gram of tranexamic acid by slow IV push.")
        XCTAssertTrue(patient.interventions.contains { $0.kind == .medication && $0.description.lowercased().contains("tranexamic acid") })
    }

    func testTXAAcronymAndUnrelatedNegation() async {
        let patient = await state("No known drug allergies, TXA was administered.")
        XCTAssertTrue(patient.interventions.contains { $0.kind == .medication && $0.description.contains("TXA") })
    }

    func testTXARequiresAffirmedAdministration() async {
        for text in ["Tranexamic acid is available.", "No TXA given.", "TXA was not administered.", "Plan to give tranexamic acid.", "Consider giving TXA.", "If hypotensive, give TXA.", "Was TXA administered?", "Giving ketamine, TXA not given.", "Giving trans exam acid.", "Gave ketamine and TXA is available.", "Instead of giving TXA, gave ketamine.", "Discussed giving TXA."] {
            let patient = await state(text)
            XCTAssertFalse(patient.interventions.contains { $0.kind == .medication && $0.description.contains("TXA") }, text)
        }
    }

    func testRepeatedTXAMentionDoesNotDuplicateSingleAdministration() async {
        let patient = await state("TXA given. Tranexamic acid administered.")
        XCTAssertEqual(patient.interventions.filter { $0.description.contains("TXA") }.count, 1)
    }

    func testAnatomicalWoundPackingRetainsStatedMaterial() async {
        let patient = await state("I packed the thigh wound with combat gauze and applied a pressure dressing.")
        XCTAssertTrue(patient.interventions.contains { $0.kind == .woundCare && $0.description.lowercased().contains("combat gauze") })
        XCTAssertTrue(patient.interventions.contains { $0.kind == .pressureDressing })
    }

    func testPackingSurvivesUnrelatedNegativeClause() async {
        let patient = await state("No head trauma, I packed the left thigh wound with gauze.")
        XCTAssertTrue(patient.interventions.contains { $0.kind == .woundCare && $0.description.lowercased().contains("gauze") })
    }

    func testPackingDoesNotInventMaterialOrCompletion() async {
        let unspecified = await state("Packed the thigh wound.")
        XCTAssertNotNil(unspecified.paws.wounds)
        XCTAssertFalse(unspecified.interventions.contains { $0.description.lowercased().contains("gauze") })
        for text in ["Have combat gauze available.", "Wound not packed with gauze.", "Did not pack the thigh wound with gauze.", "Plan to pack the thigh wound with combat gauze.", "Consider packing the wound with gauze.", "If bleeding, pack the wound with gauze.", "Was the wound packed with gauze?", "Pack the wound with gauze.", "Wound care supplies include combat gauze.", "Going to irrigate this with saline and dress it.", "Discussed packing the wound.", "Instead of packing the wound, applied a dressing."] {
            let patient = await state(text)
            XCTAssertFalse(patient.interventions.contains { $0.kind == .woundCare }, text)
        }
    }

    func testPackingMaterialMustBeAssociatedWithPacking() async {
        for text in ["Packed the wound and combat gauze is available.", "Packed the wound with a shirt and gauze is available."] {
            let patient = await state(text)
            XCTAssertNotNil(patient.paws.wounds)
            XCTAssertFalse(patient.interventions.contains { $0.kind == .woundCare && $0.description.lowercased().contains("gauze") }, text)
        }
        let used = await state("Packed the wound using combat gauze.")
        XCTAssertTrue(used.interventions.contains { $0.description == "Wound packed with combat gauze" })
    }

    func testPersistedEventsReproduceNewInterventions() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Giving one gram of tranexamic acid. Packed the thigh wound with combat gauze.")
        let expected = await engine.snapshot()
        let log = await engine.log
        let restored = PatientStateEngine.standard()
        await restored.restore(log)
        let actual = await restored.snapshot()
        XCTAssertEqual(actual, expected)
    }
}
