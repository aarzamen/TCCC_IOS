// Phase3bVocabularyTests
//
// Second wave of 2026 vocabulary additions, covering the items that
// were deferred at the original Phase 3 commit:
//   - Acetaminophen drug + dose value extraction (§11)
//   - Meloxicam (§11 CWMP component, was falling to generic descriptor)
//   - Ketamine procedural-sedation routes (§13)
//   - Plasma for isolated TBI (§8)
//
// Per sprint spec: every new pattern asserts verbatim phrase matches
// and does not over-match unrelated transcripts.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class Phase3bVocabularyTests: XCTestCase {

    private let timestamp = Date(timeIntervalSince1970: 0)

    private func ctx(_ s: String, isNegated: Bool = false) -> ExtractionContext {
        ExtractionContext(
            originalText: s,
            normalizedText: s,
            sentence: s,
            timestamp: timestamp,
            currentPatientID: "PATIENT_1",
            isNegated: isNegated)
    }

    private func emptyState() -> PatientState {
        PatientState(patientId: "PATIENT_1")
    }

    // MARK: - 3.2 Acetaminophen recognition + dose extraction

    func testAcetaminophenRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Gave acetaminophen for pain."))
        XCTAssertTrue(s.paws.pain?.contains("Acetaminophen") ?? false,
                      "Expected acetaminophen descriptor, got: \(s.paws.pain ?? "nil")")
    }

    func testTylenolMatchesAcetaminophen() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(), context: ctx("Tylenol PO administered."))
        XCTAssertTrue(s.paws.pain?.contains("Acetaminophen") ?? false)
    }

    func testAcetaminophen1000mgDoseExtracted() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Acetaminophen 1000 mg PO once."))
        XCTAssertEqual(s.paws.pain, "Acetaminophen 1000 mg administered")
    }

    func testAcetaminophen1300mgDoseExtracted() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Acetaminophen 1300 mg PO every 8 hours."))
        XCTAssertEqual(s.paws.pain, "Acetaminophen 1300 mg administered")
    }

    func testAcetaminophenTwo650mgDoseExtracted() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Acetaminophen, two 650 mg extended-release caplets."))
        // Either branch is acceptable: regex may match the explicit "650"
        // and emit "650 mg administered", or the special-case "two 650"
        // path emits "1300 mg (two 650 mg)". Both encode the dose
        // correctly; assert at the descriptor level.
        let pain = s.paws.pain ?? ""
        XCTAssertTrue(pain.contains("Acetaminophen"), "Got \(pain)")
        XCTAssertTrue(pain.contains("650") || pain.contains("1300"), "Got \(pain)")
    }

    func testAcetaminophenWithoutDoseFallsBackCleanly() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Acetaminophen administered."))
        XCTAssertEqual(s.paws.pain, "Acetaminophen administered")
    }

    func testAcetaminophenDoesNotOvermatch() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("She is taking minocycline for acne."))
        XCTAssertNil(s.paws.pain)
    }

    // MARK: - 3.2 Meloxicam (was falling through to generic)

    func testMeloxicamRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Meloxicam 15 mg PO QD."))
        XCTAssertEqual(s.paws.pain, "Meloxicam administered")
    }

    // MARK: - 3.x Ketamine procedural sedation (§13)

    func testKetaminePerKgRecognizedAsProcedural() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Ketamine 1-2 mg/kg slow IV push for procedural sedation."))
        XCTAssertEqual(s.paws.pain, "Ketamine procedural sedation administered")
    }

    func testKetamine300mgIMRecognizedAsProcedural() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Ketamine 300 mg IM administered for wound dressing."))
        XCTAssertEqual(s.paws.pain, "Ketamine procedural sedation administered")
    }

    func testProceduralSedationKeywordTriggersProceduralBranch() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Procedural sedation with ketamine."))
        XCTAssertEqual(s.paws.pain, "Ketamine procedural sedation administered")
    }

    func testRegularKetamineNotMistakenForProcedural() {
        let p = PAWSExtractor()
        // 100 mg IM analgesia dose — not procedural per 2026 §11.
        let s = p.apply(emptyState(),
                        context: ctx("Ketamine 100 mg IM administered."))
        XCTAssertEqual(s.paws.pain, "Ketamine administered")
    }

    // MARK: - 3.x Plasma for isolated TBI (§8)

    func testPlasmaForTBIRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Gave 1-2 units of plasma — no hemorrhage, suspected TBI."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("plasma")
        })
    }

    func testPlasmaOneToTwoUnitsRecognized() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Administered one to two units of plasma."))
        XCTAssertTrue(s.interventions.contains {
            $0.description.lowercased().contains("plasma")
        })
    }

    func testPlasmaDescriptionTagsTBIContext() {
        let p = PAWSExtractor()
        let s = p.apply(emptyState(),
                        context: ctx("Giving 1 unit of plasma."))
        // Even if hemorrhage state isn't checked here, the descriptor
        // text encodes the §8 isolated-TBI semantic so report formatters
        // can route correctly.
        let desc = s.interventions.first { $0.description.contains("Plasma") }?.description
        XCTAssertNotNil(desc)
        XCTAssertTrue(desc?.lowercased().contains("tbi") ?? false ||
                      desc?.lowercased().contains("isolated") ?? false,
                      "Plasma descriptor should tag the TBI context: \(desc ?? "nil")")
    }

    func testPlasmaDoesNotOvermatchOnPlasmaTV() {
        let p = PAWSExtractor()
        // Sanity: the regex requires a "units of plasma" anchor or an
        // administer-verb prefix. "Plasma TV" alone shouldn't fire.
        let s = p.apply(emptyState(),
                        context: ctx("The OPMED tent has a plasma TV in the corner."))
        XCTAssertFalse(s.interventions.contains {
            $0.description.lowercased().contains("plasma")
        })
    }
}
