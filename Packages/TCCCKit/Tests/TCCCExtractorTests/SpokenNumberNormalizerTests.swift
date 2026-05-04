// SpokenNumberNormalizerTests
//
// Exhaustive parity tests for the Swift port of `_normalise_spoken_numbers`
// from /Users/ama/TCCC_FEB_2026/src/state.py (lines 98–233).
//
// Each spoken-form literal that appears in the Python source comments,
// docstrings, or scenario fixtures has at least one assertion here. Truth
// values were captured by running the Python implementation directly against
// each input string (see the conversation log for the source-of-truth dump).

import XCTest
@testable import TCCCExtractor

final class SpokenNumberNormalizerTests: XCTestCase {

    private let n = SpokenNumberNormalizer()

    // MARK: - Literal docstring / comment examples (state.py:98–233)
    //
    // The Python docstring on `_normalise_spoken_numbers` lists these four
    // canonical examples — each becomes a direct equality test.

    func testDocExampleHeartRateOneTen() {
        XCTAssertEqual(n.normalize("heart rate one ten"), "heart rate 110")
    }

    func testDocExampleBloodPressureNinetyOverSixty() {
        XCTAssertEqual(
            n.normalize("blood pressure ninety over sixty"),
            "blood pressure 90/60")
    }

    func testDocExamplePulseOxNinetySixPercent() {
        XCTAssertEqual(
            n.normalize("pulse ox ninety-six percent"),
            "pulse ox 96%")
    }

    func testDocExampleRespiratoryRateEighteen() {
        XCTAssertEqual(
            n.normalize("respiratory rate eighteen"),
            "respiratory rate 18")
    }

    // MARK: - Spoken-to-int direct (state.py:58–95 docstring)
    //
    // The `_spoken_to_int` docstring lists every supported phrase form.

    func testSpokenToIntBareTeen() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("eighteen"), 18)
    }

    func testSpokenToIntBareTens() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("ninety"), 90)
    }

    func testSpokenToIntBareOnes() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("five"), 5)
    }

    func testSpokenToIntHyphenated() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("ninety-six"), 96)
    }

    func testSpokenToIntTensSpaceOnes() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("twenty two"), 22)
    }

    func testSpokenToIntExplicitHundredsAnd() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one hundred and five"), 105)
    }

    func testSpokenToIntMilitaryShorthandOneTen() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one ten"), 110)
    }

    func testSpokenToIntMilitaryShorthandOneTwenty() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one twenty"), 120)
    }

    func testSpokenToIntMilitaryShorthandOneThirty() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one thirty"), 130)
    }

    func testSpokenToIntBareHundred() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one hundred"), 100)
    }

    func testSpokenToIntTwoHundred() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("two hundred"), 200)
    }

    func testSpokenToIntTwoHundredTen() {
        // "two hundred and ten" -> 210 via _spoken_to_int. (Note: not all
        // call sites accept this form because the BP regex is narrower.)
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("two hundred and ten"), 210)
    }

    func testSpokenToIntSeventyEight() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("seventy-eight"), 78)
    }

    func testSpokenToIntOneAlone() {
        XCTAssertEqual(SpokenNumberNormalizer.spokenToInt("one"), 1)
    }

    func testSpokenToIntZeroReturnsNil() {
        // Mirrors Python: total > 0 guard returns None for "zero".
        XCTAssertNil(SpokenNumberNormalizer.spokenToInt("zero"))
    }

    func testSpokenToIntEmptyReturnsNil() {
        XCTAssertNil(SpokenNumberNormalizer.spokenToInt(""))
    }

    func testSpokenToIntUnknownTokenReturnsNil() {
        XCTAssertNil(SpokenNumberNormalizer.spokenToInt("random word"))
    }

    func testSpokenToIntPartiallyUnknownReturnsNil() {
        // First token "tango" is unrecognised -> entire phrase fails.
        XCTAssertNil(SpokenNumberNormalizer.spokenToInt("tango five"))
    }

    // MARK: - Heart rate context

    func testHrInlineCommentExampleOneTwenty() {
        // From state.py:66 inline comment:
        //   "BP one twenty over seventy-eight" = 120/78
        // The HR-side compound "one twenty" must resolve to 120.
        XCTAssertEqual(n.normalize("HR is one twenty"), "HR is 120")
    }

    func testHrPulseOfEighty() {
        XCTAssertEqual(n.normalize("pulse of eighty"), "pulse of 80")
    }

    func testHrHeartRateOneHundredAndFive() {
        XCTAssertEqual(
            n.normalize("heart rate one hundred and five"),
            "heart rate 105")
    }

    func testHrHeartRateNinetySix() {
        XCTAssertEqual(n.normalize("heart rate ninety-six"), "heart rate 96")
    }

    func testHrHeartRateNinetySixSpaced() {
        XCTAssertEqual(n.normalize("heart rate ninety six"), "heart rate 96")
    }

    func testHrCasePreservedHeartRate() {
        XCTAssertEqual(n.normalize("Heart Rate One Ten"), "Heart Rate 110")
    }

    func testHrCaseUpperPreserved() {
        XCTAssertEqual(n.normalize("HEART RATE NINETY"), "HEART RATE 90")
    }

    func testHrAlreadyNumericPassthrough() {
        XCTAssertEqual(n.normalize("heart rate 110"), "heart rate 110")
    }

    func testHrPulseAlreadyNumericPassthrough() {
        XCTAssertEqual(n.normalize("pulse 80"), "pulse 80")
    }

    func testHrHrAlreadyNumericPassthrough() {
        XCTAssertEqual(n.normalize("hr 110"), "hr 110")
    }

    func testHrHrIsAlreadyNumericPassthrough() {
        XCTAssertEqual(n.normalize("HR is 110"), "HR is 110")
    }

    func testHrSeventyTwo() {
        XCTAssertEqual(n.normalize("heart rate seventy-two"), "heart rate 72")
    }

    func testHrBareNinety() {
        XCTAssertEqual(n.normalize("HR ninety"), "HR 90")
    }

    func testHrOfOneTwenty() {
        XCTAssertEqual(n.normalize("heart rate of one twenty"), "heart rate of 120")
    }

    // MARK: - Blood pressure context

    func testBpDocstringNinetyOverSixty() {
        XCTAssertEqual(
            n.normalize("blood pressure ninety over sixty"),
            "blood pressure 90/60")
    }

    func testBpOneTwentyOverSeventyEight() {
        XCTAssertEqual(
            n.normalize("blood pressure one twenty over seventy-eight"),
            "blood pressure 120/78")
    }

    func testBpOneHundredOverSixtyEight() {
        XCTAssertEqual(
            n.normalize("blood pressure one hundred over sixty-eight"),
            "blood pressure 100/68")
    }

    func testBpIsNinetyOverSixty() {
        XCTAssertEqual(
            n.normalize("blood pressure is ninety over sixty"),
            "blood pressure is 90/60")
    }

    func testBpBareBpOneTwentyOverSeventy() {
        XCTAssertEqual(
            n.normalize("BP one twenty over seventy"),
            "BP 120/70")
    }

    func testBpIsOneTwentyOverSeventy() {
        XCTAssertEqual(
            n.normalize("BP is one twenty over seventy"),
            "BP is 120/70")
    }

    func testBpAlreadyNumericPassthrough() {
        XCTAssertEqual(n.normalize("bp 120 over 80"), "bp 120 over 80")
    }

    func testBpAlreadyNumericSlashPassthrough() {
        XCTAssertEqual(n.normalize("blood pressure 90/60"), "blood pressure 90/60")
    }

    func testBpHundredAndFiveDoesNotMatch() {
        // The Python BP regex's continuation alternation does not include
        // an "and" connector, so "one hundred and five" in a BP slot does
        // NOT normalize. Mirror that behavior exactly.
        XCTAssertEqual(
            n.normalize("BP is one hundred and five over seventy"),
            "BP is one hundred and five over seventy")
    }

    // MARK: - SpO2 / pulse-ox / sat context (always appends "%")

    func testSpO2DocstringExample() {
        XCTAssertEqual(n.normalize("pulse ox ninety-six percent"), "pulse ox 96%")
    }

    func testSpO2NoPercentWordStillAppends() {
        // Python `_repl_spo2` always appends "%" whether or not "percent" was spoken.
        XCTAssertEqual(n.normalize("pulse ox ninety-six"), "pulse ox 96%")
    }

    func testSpO2NinetyNine() {
        XCTAssertEqual(n.normalize("pulse ox ninety-nine"), "pulse ox 99%")
    }

    func testSpO2NinetySeven() {
        XCTAssertEqual(n.normalize("pulse ox ninety-seven"), "pulse ox 97%")
    }

    func testSpO2EightyFivePercent() {
        XCTAssertEqual(n.normalize("pulse ox eighty-five percent"), "pulse ox 85%")
    }

    func testSpO2Spo2Token() {
        XCTAssertEqual(n.normalize("spo2 ninety-eight"), "spo2 98%")
    }

    func testSpO2SatToken() {
        XCTAssertEqual(n.normalize("sat ninety-five percent"), "sat 95%")
    }

    func testSpO2O2SatToken() {
        XCTAssertEqual(n.normalize("o2 sat one hundred"), "o2 sat 100%")
    }

    func testSpO2SatOneHundredPercent() {
        XCTAssertEqual(n.normalize("sat one hundred percent"), "sat 100%")
    }

    func testSpO2IsPrefix() {
        XCTAssertEqual(n.normalize("pulse ox is ninety-six percent"), "pulse ox is 96%")
    }

    func testSpO2AlreadyNumericPassthrough() {
        // Already-numeric SpO2 does NOT get a trailing "%" appended — the
        // regex needs to match a spoken word in group 2 first.
        XCTAssertEqual(n.normalize("pulse ox 95"), "pulse ox 95")
    }

    func testSpO2AlreadyNumericSpo2Passthrough() {
        XCTAssertEqual(n.normalize("spo2 100"), "spo2 100")
    }

    func testSpO2AlreadyNumericWithPercentPassthrough() {
        XCTAssertEqual(n.normalize("sat 100 percent"), "sat 100 percent")
    }

    // MARK: - Respiratory rate context

    func testRrEighteen() {
        XCTAssertEqual(n.normalize("respiratory rate eighteen"), "respiratory rate 18")
    }

    func testRrLooksAboutEighteen() {
        // Code comment on state.py line 216 explicitly mentions:
        //   "rate looks about eighteen"
        XCTAssertEqual(
            n.normalize("respiratory rate looks about eighteen"),
            "respiratory rate looks about 18")
    }

    func testRrLooksEighteen() {
        XCTAssertEqual(n.normalize("rr looks eighteen"), "rr looks 18")
    }

    func testRrLooksAboutTwenty() {
        XCTAssertEqual(n.normalize("rr looks about twenty"), "rr looks about 20")
    }

    func testRrIsEighteen() {
        XCTAssertEqual(n.normalize("rr is eighteen"), "rr is 18")
    }

    func testRrTwenty() {
        XCTAssertEqual(n.normalize("respiratory rate twenty"), "respiratory rate 20")
    }

    func testRrFourteen() {
        XCTAssertEqual(n.normalize("respiratory rate fourteen"), "respiratory rate 14")
    }

    func testRrOfPrefixNotMatched() {
        // The RR regex prefix is "(?:respiratory\s+rate|rr)\s+(?:is\s+)?(?:looks?\s+(?:about\s+)?)?"
        // — there is no "of" alternative, so this should NOT normalize.
        XCTAssertEqual(
            n.normalize("respiratory rate of eighteen"),
            "respiratory rate of eighteen")
    }

    // MARK: - "respirations" alias is NOT recognised

    func testRespirationsTwentyEightUnchanged() {
        // The brief gives this example, but the Python regex only knows
        // "respiratory rate" / "rr" — NOT "respirations". Mirror Python.
        XCTAssertEqual(
            n.normalize("respirations twenty eight"),
            "respirations twenty eight")
    }

    // MARK: - Non-vital text must pass through unchanged

    func testNonClinicalFiveMinutesAgo() {
        XCTAssertEqual(
            n.normalize("Five minutes ago he was conscious."),
            "Five minutes ago he was conscious.")
    }

    func testNonClinicalTimeFourteenThirtyTwo() {
        XCTAssertEqual(
            n.normalize("Time of application is fourteen thirty-two."),
            "Time of application is fourteen thirty-two.")
    }

    func testNonClinicalThreeCentimeters() {
        XCTAssertEqual(n.normalize("three centimeters"), "three centimeters")
    }

    func testNonClinicalTwentyMeters() {
        XCTAssertEqual(n.normalize("twenty meters"), "twenty meters")
    }

    func testNonClinicalEighteenGauge() {
        XCTAssertEqual(n.normalize("eighteen gauge"), "eighteen gauge")
    }

    func testNonClinicalGcsFifteen() {
        XCTAssertEqual(n.normalize("GCS fifteen"), "GCS fifteen")
    }

    func testNonClinicalEightOutOfTen() {
        XCTAssertEqual(n.normalize("eight out of ten"), "eight out of ten")
    }

    func testNonClinicalPlainText() {
        XCTAssertEqual(n.normalize("Just text without numbers."), "Just text without numbers.")
    }

    func testNonClinicalEmptyString() {
        XCTAssertEqual(n.normalize(""), "")
    }

    func testNonClinicalBareSpokenNumberIsLeftAlone() {
        // "one twenty" alone (no vital prefix) is not a vital — must pass.
        XCTAssertEqual(n.normalize("one twenty"), "one twenty")
    }

    func testNonClinicalBareOneHundredIsLeftAlone() {
        XCTAssertEqual(n.normalize("one hundred"), "one hundred")
    }

    // MARK: - Compound vital sentences

    func testCompoundVitalsScenario1Style() {
        let input = "Vitals: heart rate one ten, blood pressure ninety over sixty, " +
                    "pulse ox ninety-six percent, respiratory rate eighteen."
        let expected = "Vitals: heart rate 110, blood pressure 90/60, " +
                       "pulse ox 96%, respiratory rate 18."
        XCTAssertEqual(n.normalize(input), expected)
    }

    func testCompoundVitalsScenario3Style() {
        let input = "Vitals are heart rate seventy-two, " +
                    "blood pressure one twenty over seventy-eight, " +
                    "pulse ox ninety-nine, respiratory rate fourteen."
        let expected = "Vitals are heart rate 72, blood pressure 120/78, " +
                       "pulse ox 99%, respiratory rate 14."
        XCTAssertEqual(n.normalize(input), expected)
    }

    func testCompoundVitalsScenario4Style() {
        let input = "Vitals: heart rate one hundred and five, " +
                    "blood pressure one hundred over sixty-eight, " +
                    "pulse ox ninety-seven, respiratory rate twenty."
        let expected = "Vitals: heart rate 105, blood pressure 100/68, " +
                       "pulse ox 97%, respiratory rate 20."
        XCTAssertEqual(n.normalize(input), expected)
    }

    // MARK: - Scenario fixtures (bundled as resources)
    //
    // These mirror the `test_scenario1_spoken_vitals_*` tests in
    // /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py — but at the
    // normalizer layer we assert string substring presence rather than
    // engine-extracted values.

    private func loadScenario(_ basename: String) throws -> String {
        // The fixture filename in Resources/scenarios/ already ends in .txt,
        // so we strip the extension before handing the basename to Bundle.
        let stem = (basename as NSString).deletingPathExtension
        guard let url = Bundle.module.url(
            forResource: stem,
            withExtension: "txt",
            subdirectory: "scenarios"
        ) else {
            XCTFail("Missing bundled scenario resource: \(stem).txt")
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testScenario1NormalizedHr() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("heart rate 110"),
            "Expected 'heart rate 110' in normalized scenario 1, got:\n\(out)")
    }

    func testScenario1NormalizedBp() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("blood pressure 90/60"),
            "Expected 'blood pressure 90/60' in normalized scenario 1, got:\n\(out)")
    }

    func testScenario1NormalizedSpo2() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("pulse ox 96%"),
            "Expected 'pulse ox 96%' in normalized scenario 1, got:\n\(out)")
    }

    func testScenario1NormalizedRr() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let out = n.normalize(raw)
        // The fixture has both "respiratory rate looks about eighteen" and
        // "respiratory rate eighteen" — both should normalize to "18".
        XCTAssertTrue(
            out.contains("respiratory rate looks about 18"),
            "Expected 'respiratory rate looks about 18' in scenario 1, got:\n\(out)")
        XCTAssertTrue(
            out.contains("respiratory rate 18"),
            "Expected 'respiratory rate 18' in scenario 1, got:\n\(out)")
    }

    func testScenario3NormalizedHr() throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("heart rate 72"),
            "Expected 'heart rate 72' in normalized scenario 3, got:\n\(out)")
    }

    func testScenario3NormalizedBp() throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("blood pressure 120/78"),
            "Expected 'blood pressure 120/78' in normalized scenario 3, got:\n\(out)")
    }

    func testScenario3NormalizedSpo2() throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("pulse ox 99%"),
            "Expected 'pulse ox 99%' in normalized scenario 3, got:\n\(out)")
    }

    func testScenario3NormalizedRr() throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("respiratory rate 14"),
            "Expected 'respiratory rate 14' in normalized scenario 3, got:\n\(out)")
    }

    func testScenario4NormalizedHr() throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("heart rate 105"),
            "Expected 'heart rate 105' in normalized scenario 4, got:\n\(out)")
    }

    func testScenario4NormalizedBp() throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("blood pressure 100/68"),
            "Expected 'blood pressure 100/68' in normalized scenario 4, got:\n\(out)")
    }

    func testScenario4NormalizedSpo2() throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("pulse ox 97%"),
            "Expected 'pulse ox 97%' in normalized scenario 4, got:\n\(out)")
    }

    func testScenario4NormalizedRr() throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        let out = n.normalize(raw)
        XCTAssertTrue(
            out.contains("respiratory rate 20"),
            "Expected 'respiratory rate 20' in normalized scenario 4, got:\n\(out)")
    }

    func testScenario2HasNoSpokenVitalsButIsClean() throws {
        // Scenario 2 contains no spoken vital signs — normalization must not
        // alter or corrupt it.
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let out = n.normalize(raw)
        XCTAssertEqual(out, raw, "Scenario 2 has no spoken vitals; output must match input verbatim")
    }

    // MARK: - Idempotence + repeat-call stability

    func testNormalizeIsIdempotent() {
        let input = "Vitals: heart rate one ten, blood pressure ninety over sixty, " +
                    "pulse ox ninety-six percent, respiratory rate eighteen."
        let once = n.normalize(input)
        let twice = n.normalize(once)
        XCTAssertEqual(once, twice, "Normalizing twice must equal normalizing once")
    }

    func testNormalizerIsReusable() {
        // Build a single normalizer instance and re-use it across many calls.
        let m = SpokenNumberNormalizer()
        XCTAssertEqual(m.normalize("heart rate one ten"), "heart rate 110")
        XCTAssertEqual(m.normalize("blood pressure ninety over sixty"), "blood pressure 90/60")
        XCTAssertEqual(m.normalize("pulse ox ninety-six percent"), "pulse ox 96%")
        XCTAssertEqual(m.normalize("respiratory rate eighteen"), "respiratory rate 18")
    }
}
