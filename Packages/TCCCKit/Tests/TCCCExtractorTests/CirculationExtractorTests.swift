// CirculationExtractorTests
//
// Mirrors the Python regression suite for circulation findings:
//   - /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py
//     (TestWordBoundaryFalsePositives — the IV \biv\b boundary tests).
//   - Scenario-level extraction from scenarios 1, 3, 4 (IV access, skin signs,
//     pulse status).
//
// Constructs an `ExtractionContext` directly per sentence and applies the
// extractor — no engine dependency.

import XCTest
@testable import TCCCDomain
@testable import TCCCExtractor

final class CirculationExtractorTests: XCTestCase {

    private let extractor = CirculationExtractor()
    private let timestamp = Date(timeIntervalSince1970: 0)

    // MARK: - Helpers

    private func makeContext(
        sentence: String,
        isNegated: Bool = false
    ) -> ExtractionContext {
        ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: timestamp,
            currentPatientID: "PATIENT_1",
            isNegated: isNegated
        )
    }

    private func emptyState() -> PatientState {
        PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Pulse

    func testRadialPulsePresent() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Radial pulse is present.")
        )
        XCTAssertEqual(s.march.pulseStatus, "radial present")
    }

    func testStrongRadialPulseFromQualityForm() {
        // "strong radial pulse" hits the second pattern and yields "strong radial".
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "He's got a strong radial pulse on the right.")
        )
        XCTAssertEqual(s.march.pulseStatus, "strong radial")
    }

    func testWeakPulse() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Pulse is weak.")
        )
        // Python: rule 0 (radial pulse) misses, rule 1 ("(quality) pulse")
        // also misses because there's no "weak pulse" subsequence. Rule 2
        // ("pulse (is) (quality)") matches and the lambda returns just
        // m.group(2) = "weak" (no "radial" prefix because we never said radial).
        XCTAssertEqual(s.march.pulseStatus, "weak")
    }

    func testWeakPulseFromQualityForm() {
        // The "(quality) pulse" form does emit "<quality> radial".
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "He has a weak pulse on the right.")
        )
        XCTAssertEqual(s.march.pulseStatus, "weak radial")
    }

    func testThreadyPulse() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Patient has thready pulse.")
        )
        XCTAssertEqual(s.march.pulseStatus, "thready radial")
    }

    func testAbsentRadialPulseFirstRule() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Radial pulse absent.")
        )
        XCTAssertEqual(s.march.pulseStatus, "radial absent")
    }

    // MARK: - Skin signs

    func testSkinWarmAndDry() {
        // Two-word pattern (warm + dry) is rule index 1, but rule 0 (bare
        // "skin warm") also matches and wins — Python iterates in order.
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Skin is warm and dry.")
        )
        XCTAssertEqual(s.march.skinSigns, "warm")
    }

    func testSkinWarmDiaphoreticTwoWordRule() {
        // "warm and slightly diaphoretic" — rule 0 matches "skin warm" first
        // and assigns "warm" (Python lambda returns m.group(2)).
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Skin is warm and slightly diaphoretic.")
        )
        XCTAssertEqual(s.march.skinSigns, "warm")
    }

    func testColdAndClammy() {
        // No "skin" prefix → rule 0 misses, rule 1 catches "cold and clammy".
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "He's cold and clammy.")
        )
        XCTAssertEqual(s.march.skinSigns, "cold clammy")
    }

    func testSkinPale() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Skin is pale.")
        )
        XCTAssertEqual(s.march.skinSigns, "pale")
    }

    // MARK: - IV / IO interventions

    func testStartingAnIvEighteenGauge() {
        // Mirrors Python TestWordBoundaryFalsePositives.test_real_iv_is_detected
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Starting an IV, eighteen gauge, left AC.")
        )
        XCTAssertEqual(s.march.circulationIntervention, "IV access")
        XCTAssertTrue(s.interventions.contains { $0.kind == .ivAccess })
        XCTAssertTrue(s.interventions.contains { $0.description == "IV access established" })
    }

    func testIntravenousLineAlsoMatches() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Establishing intravenous access.")
        )
        XCTAssertEqual(s.march.circulationIntervention, "IV access")
    }

    func testIoAccessForIntraosseous() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Going for intraosseous access.")
        )
        XCTAssertEqual(s.march.circulationIntervention, "IO access")
        XCTAssertTrue(s.interventions.contains { $0.kind == .ioAccess })
        XCTAssertTrue(s.interventions.contains { $0.description == "IO access established" })
    }

    // MARK: - Word boundary regressions (P1 #6)

    func testFiveDoesNotTriggerIv() {
        // Mirrors Python TestWordBoundaryFalsePositives.test_no_iv_from_five
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "five five five")
        )
        XCTAssertNotEqual(s.march.circulationIntervention, "IV access")
        XCTAssertFalse(s.interventions.contains { $0.kind == .ivAccess })
    }

    func testFiveInSentenceDoesNotTriggerIv() {
        // Mirrors Python TestWordBoundaryFalsePositives.test_no_iv_from_five_in_sentence
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "He says the pain is about an eight or five out of ten.")
        )
        XCTAssertNotEqual(s.march.circulationIntervention, "IV access")
    }

    func testGiveItDoesNotTriggerIv() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Give it some time.")
        )
        XCTAssertNotEqual(s.march.circulationIntervention, "IV access")
    }

    func testArrivedDoesNotTriggerIv() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "We arrived on scene.")
        )
        XCTAssertNotEqual(s.march.circulationIntervention, "IV access")
    }

    // MARK: - Intervention deduplication

    func testIvDeduplicationAcrossSentences() {
        let first = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Starting an IV, eighteen gauge.")
        )
        let second = extractor.apply(
            first,
            context: makeContext(sentence: "Confirming IV is patent.")
        )
        XCTAssertEqual(
            second.interventions.filter { $0.description == "IV access established" }.count,
            1
        )
    }

    // MARK: - Negation flag

    func testIsNegatedSuppressesPulse() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No radial pulse present.",
                isNegated: true
            )
        )
        XCTAssertNil(s.march.pulseStatus)
    }

    func testIsNegatedSuppressesIv() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No IV needed at this time.",
                isNegated: true
            )
        )
        XCTAssertNil(s.march.circulationIntervention)
        XCTAssertTrue(s.interventions.isEmpty)
    }

    // MARK: - Scenario-level mirrors

    func testScenario1IvIsDetected() throws {
        let scenario = try loadScenario("scenario_1_gsw_thigh.txt")
        let s = applyExtractorToScenario(scenario)
        XCTAssertEqual(s.march.circulationIntervention, "IV access")
        XCTAssertTrue(s.interventions.contains { $0.description == "IV access established" })
    }

    func testScenario4IvIsDetected() throws {
        let scenario = try loadScenario("scenario_4_femur_fracture.txt")
        let s = applyExtractorToScenario(scenario)
        XCTAssertEqual(s.march.circulationIntervention, "IV access")
    }

    func testScenario3StrongRadialPulse() throws {
        let scenario = try loadScenario("scenario_3_mre_laceration.txt")
        let s = applyExtractorToScenario(scenario)
        XCTAssertEqual(s.march.pulseStatus, "strong radial")
    }

    // MARK: - Helpers

    private func applyExtractorToScenario(_ scenario: String) -> PatientState {
        let sentences = SentenceTokenizer().tokenize(scenario)
        let negDetector = NegationDetector()
        var s = emptyState()
        for sentence in sentences {
            let isNegated = negDetector.sentenceHasNegationMarker(sentence)
            s = extractor.apply(
                s,
                context: makeContext(sentence: sentence, isNegated: isNegated)
            )
        }
        return s
    }

    private func loadScenario(_ filename: String) throws -> String {
        let stem = (filename as NSString).deletingPathExtension
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
}
