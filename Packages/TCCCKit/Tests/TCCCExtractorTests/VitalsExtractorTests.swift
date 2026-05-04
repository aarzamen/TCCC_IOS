// VitalsExtractorTests
//
// Mirrors the Python vital-sign assertions from
// /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py and
// /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py, plus exhaustive
// regex-pattern coverage for HR / BP / SpO2 / RR variants.
//
// VitalsExtractor operates on the post-normalised sentence, so the tests
// supply already-normalised numeric forms ("HR 138", "BP 90/60") rather
// than spoken forms — that's the engine's contract documented in
// `ExtractionContext.sentence`.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class VitalsExtractorTests: XCTestCase {

    private let extractor = VitalsExtractor()

    // MARK: - Helpers

    /// Build a default ExtractionContext for the supplied sentence.
    private func ctx(
        _ sentence: String,
        isNegated: Bool = false,
        patient: String = "PATIENT_1"
    ) -> ExtractionContext {
        return ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(timeIntervalSince1970: 0),
            currentPatientID: patient,
            isNegated: isNegated
        )
    }

    private func emptyState() -> PatientState {
        return PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Heart rate (state.py:443 r"(?:heart\s*rate|hr|pulse)\s*(?:is\s*|of\s*)?(\d+)")

    func testHRSpaceFormHeartRate() {
        let s = extractor.apply(emptyState(), context: ctx("heart rate 138"))
        XCTAssertEqual(s.vitals.hr, 138)
    }

    func testHRAbbreviationHR() {
        let s = extractor.apply(emptyState(), context: ctx("HR 110"))
        XCTAssertEqual(s.vitals.hr, 110)
    }

    func testHRPulseForm() {
        let s = extractor.apply(emptyState(), context: ctx("pulse 92"))
        XCTAssertEqual(s.vitals.hr, 92)
    }

    func testHRWithIsConnective() {
        let s = extractor.apply(emptyState(), context: ctx("heart rate is 95"))
        XCTAssertEqual(s.vitals.hr, 95)
    }

    func testHRWithOfConnective() {
        let s = extractor.apply(emptyState(), context: ctx("heart rate of 80"))
        XCTAssertEqual(s.vitals.hr, 80)
    }

    func testHRMixedCase() {
        let s = extractor.apply(emptyState(), context: ctx("Heart Rate 105"))
        XCTAssertEqual(s.vitals.hr, 105)
    }

    func testHRSpokenAlreadyNormalised105() {
        // From scenario_4 fixture: "heart rate one hundred and five"
        // normalised by SpokenNumberNormalizer to "heart rate 105"
        let s = extractor.apply(
            emptyState(),
            context: ctx("Vitals: heart rate 105, blood pressure 100/68, " +
                         "pulse ox 97, respiratory rate 20."))
        XCTAssertEqual(s.vitals.hr, 105)
    }

    func testHROutOfRangeIsDropped() {
        // Vitals init drops out-of-range values silently (Vitals.hrRange = 0…300).
        let s = extractor.apply(emptyState(), context: ctx("HR 999"))
        XCTAssertNil(s.vitals.hr, "HR 999 is out of physiological range")
    }

    // MARK: - Blood pressure (state.py:445 r"(?:blood\s*pressure|bp)\s*(?:is\s*)?(\d+)\s*(?:over|/)\s*(\d+)")

    func testBPSlashForm() {
        let s = extractor.apply(emptyState(), context: ctx("BP 80/40"))
        XCTAssertEqual(s.vitals.bp?.systolic, 80)
        XCTAssertEqual(s.vitals.bp?.diastolic, 40)
        XCTAssertEqual(s.vitals.bp?.palpated, false)
    }

    func testBPOverForm() {
        let s = extractor.apply(
            emptyState(), context: ctx("blood pressure 90 over 60"))
        XCTAssertEqual(s.vitals.bp?.systolic, 90)
        XCTAssertEqual(s.vitals.bp?.diastolic, 60)
        XCTAssertEqual(s.vitals.bp?.palpated, false)
    }

    func testBPPalpatedSuffixCapitalP() {
        let s = extractor.apply(emptyState(), context: ctx("BP 80/40 P"))
        XCTAssertEqual(s.vitals.bp?.systolic, 80)
        XCTAssertEqual(s.vitals.bp?.diastolic, 40)
        XCTAssertTrue(s.vitals.bp?.palpated ?? false,
                      "Trailing 'P' should mark BP as palpated")
    }

    func testBPPalpatedFullWord() {
        let s = extractor.apply(
            emptyState(), context: ctx("BP 90/50 palpated"))
        XCTAssertEqual(s.vitals.bp?.systolic, 90)
        XCTAssertEqual(s.vitals.bp?.diastolic, 50)
        XCTAssertTrue(s.vitals.bp?.palpated ?? false)
    }

    func testBPWithIsConnective() {
        let s = extractor.apply(
            emptyState(), context: ctx("blood pressure is 120/80"))
        XCTAssertEqual(s.vitals.bp?.systolic, 120)
        XCTAssertEqual(s.vitals.bp?.diastolic, 80)
    }

    func testBPSpokenAlreadyNormalised12078() {
        // From scenario_3: "blood pressure one twenty over seventy-eight"
        // normalises to "blood pressure 120/78"
        let s = extractor.apply(
            emptyState(),
            context: ctx("Vitals are heart rate 72, blood pressure 120/78, " +
                         "pulse ox 99, respiratory rate 14."))
        XCTAssertEqual(s.vitals.bp?.systolic, 120)
        XCTAssertEqual(s.vitals.bp?.diastolic, 78)
    }

    // MARK: - SpO2 (state.py:446 r"(?:pulse\s*ox|spo2|sat|o2\s*sat)\s*(?:is\s*)?(\d+)\s*%?")

    func testSpO2PulseOxForm() {
        let s = extractor.apply(emptyState(), context: ctx("pulse ox 92"))
        XCTAssertEqual(s.vitals.spo2, 92)
    }

    func testSpO2WithPercent() {
        let s = extractor.apply(emptyState(), context: ctx("pulse ox 96%"))
        XCTAssertEqual(s.vitals.spo2, 96)
    }

    func testSpO2Spo2Form() {
        let s = extractor.apply(emptyState(), context: ctx("SpO2 99"))
        XCTAssertEqual(s.vitals.spo2, 99)
    }

    func testSpO2SatForm() {
        let s = extractor.apply(emptyState(), context: ctx("sat 88"))
        XCTAssertEqual(s.vitals.spo2, 88)
    }

    func testSpO2O2SatForm() {
        let s = extractor.apply(emptyState(), context: ctx("O2 sat 91"))
        XCTAssertEqual(s.vitals.spo2, 91)
    }

    func testSpO2WithIsConnective() {
        let s = extractor.apply(emptyState(), context: ctx("pulse ox is 94"))
        XCTAssertEqual(s.vitals.spo2, 94)
    }

    // MARK: - RR (state.py:447 r"(?:respiratory\s*rate|rr)\s*(?:is\s*|looks?\s*(?:about\s*)?)?(\d+)")

    func testRRSpaceForm() {
        let s = extractor.apply(
            emptyState(), context: ctx("respiratory rate 18"))
        XCTAssertEqual(s.vitals.rr, 18)
    }

    func testRRAbbreviation() {
        let s = extractor.apply(emptyState(), context: ctx("RR 22"))
        XCTAssertEqual(s.vitals.rr, 22)
    }

    func testRRWithLooksAbout() {
        // From scenario_1 fixture: "respiratory rate looks about eighteen"
        // -> already normalised to "respiratory rate looks about 18"
        let s = extractor.apply(
            emptyState(),
            context: ctx("respiratory rate looks about 18"))
        XCTAssertEqual(s.vitals.rr, 18)
    }

    func testRRDoesNotOverrideExistingValue() {
        // Mirror state.py:817–820 — RR is only set if not already present.
        var seed = emptyState()
        seed.vitals = Vitals(rr: 14)
        let s = extractor.apply(seed, context: ctx("RR 30"))
        XCTAssertEqual(s.vitals.rr, 14, "Existing RR should not be overwritten")
    }

    // MARK: - Combined / scenario-derived sentences

    func testCombinedVitalsLineScenario1() {
        // scenario_1 final vitals line, post-normalisation.
        let sentence =
            "Vitals: heart rate 110, blood pressure 90/60, " +
            "pulse ox 96%, respiratory rate 18."
        let s = extractor.apply(emptyState(), context: ctx(sentence))
        XCTAssertEqual(s.vitals.hr, 110)
        XCTAssertEqual(s.vitals.bp?.systolic, 90)
        XCTAssertEqual(s.vitals.bp?.diastolic, 60)
        XCTAssertEqual(s.vitals.spo2, 96)
        XCTAssertEqual(s.vitals.rr, 18)
    }

    func testCombinedVitalsLineScenario4() {
        let sentence =
            "Vitals: heart rate 105, blood pressure 100/68, " +
            "pulse ox 97, respiratory rate 20."
        let s = extractor.apply(emptyState(), context: ctx(sentence))
        XCTAssertEqual(s.vitals.hr, 105)
        XCTAssertEqual(s.vitals.bp?.systolic, 100)
        XCTAssertEqual(s.vitals.bp?.diastolic, 68)
        XCTAssertEqual(s.vitals.spo2, 97)
        XCTAssertEqual(s.vitals.rr, 20)
    }

    // MARK: - Negation (Swift-only extension)

    func testNegationSuppressesHR() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no measurable heart rate", isNegated: true))
        XCTAssertNil(s.vitals.hr)
    }

    func testNegationSuppressesBP() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no measurable BP 0/0", isNegated: true))
        XCTAssertNil(s.vitals.bp)
    }

    func testNegationSuppressesSpO2() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no pulse ox 0", isNegated: true))
        XCTAssertNil(s.vitals.spo2)
    }

    // MARK: - State preservation

    func testNoMatchPreservesState() {
        var seed = emptyState()
        seed.vitals = Vitals(hr: 80, spo2: 99)
        let s = extractor.apply(seed, context: ctx("airway is patent"))
        XCTAssertEqual(s.vitals.hr, 80)
        XCTAssertEqual(s.vitals.spo2, 99)
    }

    func testPartialMatchPreservesOtherFields() {
        var seed = emptyState()
        seed.vitals = Vitals(hr: 80, spo2: 99, gcs: 14)
        let s = extractor.apply(seed, context: ctx("BP 110/70"))
        XCTAssertEqual(s.vitals.hr, 80)
        XCTAssertEqual(s.vitals.spo2, 99)
        XCTAssertEqual(s.vitals.gcs, 14, "GCS belongs to head extractor; vitals pass must preserve it")
        XCTAssertEqual(s.vitals.bp?.systolic, 110)
        XCTAssertEqual(s.vitals.bp?.diastolic, 70)
    }

    func testHROverwriteOnNewSentence() {
        var seed = emptyState()
        seed.vitals = Vitals(hr: 80)
        let s = extractor.apply(seed, context: ctx("HR 138"))
        XCTAssertEqual(s.vitals.hr, 138, "Newer HR should overwrite older")
    }

    // MARK: - GCS is NOT extracted by VitalsExtractor (state.py routes through head)

    func testVitalsExtractorIgnoresGCS() {
        // Mirror the Python contract: GCS lives in `_extract_head_hypothermia`,
        // not `_extract_vitals`. VitalsExtractor must leave GCS untouched.
        let s = extractor.apply(emptyState(), context: ctx("GCS 15"))
        XCTAssertNil(s.vitals.gcs, "GCS extraction is the head extractor's job, not vitals")
    }
}
