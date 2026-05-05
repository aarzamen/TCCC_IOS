// PAWSExtractorTests
//
// Mirrors the Python PAWS assertions implicit in
// /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py (scenario 4 has the
// canonical "Combat pill pack" + "Tylenol and Meloxicam" line) plus the
// regex coverage for the three PAWS pattern groups (pain meds, antibiotics,
// wound care) at state.py:472–479.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PAWSExtractorTests: XCTestCase {

    private let extractor = PAWSExtractor()

    private func ctx(
        _ sentence: String,
        isNegated: Bool = false
    ) -> ExtractionContext {
        return ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(timeIntervalSince1970: 0),
            currentPatientID: "PATIENT_1",
            isNegated: isNegated
        )
    }

    private func emptyState() -> PatientState {
        return PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Pain medications (state.py:474, 901–912)

    func testCombatPillPackRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Giving him the combat pill pack, " +
                         "Tylenol and Meloxicam."))
        XCTAssertEqual(s.paws.pain, "Combat pill pack administered")
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .painManagement)
        XCTAssertEqual(s.interventions.first?.description,
                       "Combat pill pack administered")
    }

    func testKetamineRecognised() {
        let s = extractor.apply(
            emptyState(), context: ctx("Pushing 50mg ketamine IM."))
        XCTAssertEqual(s.paws.pain, "Ketamine administered")
        XCTAssertEqual(s.interventions.first?.description, "Ketamine administered")
    }

    func testTylenolMatchesAcetaminophenWithDose() {
        // 2026 sprint Phase 3b: Tylenol now resolves through the
        // acetaminophen sub-classifier and the dose extractor pulls the
        // numeric value out of the same sentence.
        let s = extractor.apply(
            emptyState(),
            context: ctx("Gave him 1000mg of Tylenol for the pain."))
        XCTAssertEqual(s.paws.pain, "Acetaminophen 1000 mg administered")
    }

    func testMeloxicamHasItsOwnDescriptor() {
        // 2026 sprint Phase 3b: Meloxicam recognized as a CWMP component.
        let s = extractor.apply(
            emptyState(), context: ctx("Started him on Meloxicam."))
        XCTAssertEqual(s.paws.pain, "Meloxicam administered")
    }

    func testMotrinFallsBackToGenericPainMed() {
        let s = extractor.apply(
            emptyState(), context: ctx("He took some Motrin."))
        XCTAssertEqual(s.paws.pain, "Pain medication administered")
    }

    func testIbuprofenFallsBackToGenericPainMed() {
        let s = extractor.apply(
            emptyState(), context: ctx("Gave 800mg ibuprofen."))
        XCTAssertEqual(s.paws.pain, "Pain medication administered")
    }

    func testGenericPainMedsPhrase() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Administered pain meds."))
        XCTAssertEqual(s.paws.pain, "Pain medication administered")
    }

    func testCombatPillPackBeatsGenericClassifier() {
        // "combat pill pack" should win over the generic pain_meds branch
        // even when Tylenol / Meloxicam appear in the same sentence (the
        // Python sub-classifier check uses combat-pill-pack first).
        let s = extractor.apply(
            emptyState(),
            context: ctx("Giving him a combat pill pack containing tylenol."))
        XCTAssertEqual(s.paws.pain, "Combat pill pack administered")
    }

    // MARK: - Antibiotics (state.py:476, 914–923)

    func testMoxifloxacinRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Pushed 400mg moxifloxacin PO."))
        XCTAssertEqual(s.paws.antibiotics, "Moxifloxacin administered")
        XCTAssertEqual(s.interventions.first?.kind, .antibiotic)
    }

    func testMoxiAbbreviationRecognised() {
        let s = extractor.apply(
            emptyState(), context: ctx("Started moxi."))
        XCTAssertEqual(s.paws.antibiotics, "Moxifloxacin administered")
    }

    func testGenericAntibiotic() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Started broad-spectrum antibiotics."))
        XCTAssertEqual(s.paws.antibiotics, "Antibiotics administered")
    }

    func testErtapenemFallsBackToGeneric() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Pushed ertapenem 1g IV."))
        XCTAssertEqual(s.paws.antibiotics, "Antibiotics administered")
    }

    // MARK: - Wound care (state.py:478, 925–929)

    func testIrrigateRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Going to irrigate this with saline and dress it."))
        XCTAssertEqual(s.paws.wounds, "Wound care performed")
        XCTAssertEqual(s.interventions.first?.kind, .woundCare)
    }

    func testIrrigationRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Performed irrigation of the wound with saline."))
        XCTAssertEqual(s.paws.wounds, "Wound care performed")
    }

    func testWoundPackingRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Packed the wound with combat gauze."))
        XCTAssertEqual(s.paws.wounds, "Wound care performed")
    }

    func testWoundCarePhraseRecognised() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Continued wound care en route."))
        XCTAssertEqual(s.paws.wounds, "Wound care performed")
    }

    // MARK: - Negation (Swift-only extension)

    func testNegationSuppressesPain() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("denies any pain meds today", isNegated: true))
        XCTAssertNil(s.paws.pain)
        XCTAssertEqual(s.interventions.count, 0)
    }

    func testNegationSuppressesAntibiotics() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no antibiotics needed", isNegated: true))
        XCTAssertNil(s.paws.antibiotics)
    }

    func testNegationSuppressesWoundCare() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no wound care performed yet", isNegated: true))
        XCTAssertNil(s.paws.wounds)
    }

    // MARK: - State preservation / no-overwrite (state.py:909–912)

    func testNoMatchPreservesState() {
        let s = extractor.apply(
            emptyState(), context: ctx("airway is patent"))
        XCTAssertNil(s.paws.pain)
        XCTAssertNil(s.paws.antibiotics)
        XCTAssertNil(s.paws.wounds)
        XCTAssertEqual(s.interventions.count, 0)
    }

    func testExistingPainNotOverwritten() {
        // Mirror Python guard: if "pain"/"pill pack"/"ketamine" already in
        // interventions, do not append again. Swift uses the typed
        // `state.paws.pain` slot — non-nil means already-recorded.
        var seed = emptyState()
        seed.paws.pain = "Combat pill pack administered"
        let s = extractor.apply(
            seed,
            context: ctx("Pushed ketamine IM."))
        XCTAssertEqual(s.paws.pain, "Combat pill pack administered",
                       "Existing pain descriptor must not be overwritten")
    }

    func testExistingAntibioticsNotOverwritten() {
        var seed = emptyState()
        seed.paws.antibiotics = "Moxifloxacin administered"
        let s = extractor.apply(
            seed,
            context: ctx("Switched to ertapenem."))
        XCTAssertEqual(s.paws.antibiotics, "Moxifloxacin administered")
    }

    // MARK: - Multi-category sentences

    func testPainAndAntibioticsTogether() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Combat pill pack and moxifloxacin administered."))
        XCTAssertEqual(s.paws.pain, "Combat pill pack administered")
        XCTAssertEqual(s.paws.antibiotics, "Moxifloxacin administered")
        XCTAssertEqual(s.interventions.count, 2)
    }

    func testInterventionsTimestampPropagated() {
        let when = Date(timeIntervalSince1970: 12345.0)
        let context = ExtractionContext(
            originalText: "Combat pill pack.",
            normalizedText: "Combat pill pack.",
            sentence: "Combat pill pack.",
            timestamp: when,
            currentPatientID: "PATIENT_1",
            isNegated: false
        )
        let s = extractor.apply(emptyState(), context: context)
        XCTAssertEqual(s.interventions.first?.timestamp, when)
    }
}
