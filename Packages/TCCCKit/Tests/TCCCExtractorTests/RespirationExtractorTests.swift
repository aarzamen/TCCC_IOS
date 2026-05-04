// RespirationExtractorTests
//
// Mirrors the Python regression suite for respiration findings:
//   - /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py (no_pneumothorax,
//     bilateral breath sounds, pneumothorax + chest seal, RR-derived status).
//   - /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py (TestPneumothoraxNegation).
//
// Constructs an `ExtractionContext` directly per sentence and applies the
// extractor — no engine dependency.

import XCTest
@testable import TCCCDomain
@testable import TCCCExtractor

final class RespirationExtractorTests: XCTestCase {

    private let extractor = RespirationExtractor()
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

    // MARK: - Breath sounds

    func testBilateralEqualBreathSounds() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Breath sounds bilateral and equal, chest rise symmetric.")
        )
        XCTAssertEqual(s.march.breathSounds, "bilateral equal")
    }

    func testBilateralBreathSoundsClear() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Bilateral breath sounds clear.")
        )
        XCTAssertEqual(s.march.breathSounds, "bilateral equal")
    }

    func testDiminishedLeftSide() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Breath sounds diminished on the left.")
        )
        XCTAssertEqual(s.march.breathSounds, "diminished left")
    }

    func testDiminishedRightSideNoPreposition() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Diminished right.")
        )
        XCTAssertEqual(s.march.breathSounds, "diminished right")
    }

    func testLeftSideDiminishedFormat() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Left side diminished.")
        )
        XCTAssertEqual(s.march.breathSounds, "diminished left")
    }

    // MARK: - Pneumothorax (positive)

    func testPossiblePneumothoraxIsRecorded() {
        // Mirrors Python TestPneumothoraxNegation.test_positive_pneumothorax_is_recorded
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Possible pneumothorax on the left side.")
        )
        XCTAssertEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    func testTensionMatchesPneumothorax() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Will monitor for tension.")
        )
        XCTAssertEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    // MARK: - Pneumothorax (negation)

    func testNegatedPneumothoraxNotRecorded() {
        // Mirrors Python TestPneumothoraxNegation.test_negated_pneumothorax_not_recorded
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "No signs of pneumothorax.")
        )
        XCTAssertNotEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    func testNegatedTensionNotRecorded() {
        // Mirrors Python TestPneumothoraxNegation.test_negated_tension_not_recorded
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "No tension present, bilateral breath sounds clear.")
        )
        XCTAssertNotEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    func testNoChestTraumaNotRecorded() {
        // Mirrors Python TestPneumothoraxNegation.test_no_chest_trauma_not_recorded
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "No chest trauma identified.")
        )
        XCTAssertNotEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    // MARK: - Interventions

    func testChestSealApplied() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Applying chest seal to the left chest.")
        )
        XCTAssertEqual(s.march.respirationIntervention, "Chest seal applied")
        XCTAssertTrue(s.interventions.contains { $0.kind == .chestSeal })
        XCTAssertTrue(s.interventions.contains { $0.description == "Chest seal applied" })
    }

    func testOcclusiveAlsoTriggersChestSeal() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Placing occlusive dressing.")
        )
        XCTAssertEqual(s.march.respirationIntervention, "Chest seal applied")
    }

    func testNeedleDecompression() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Performing needle decompression.")
        )
        XCTAssertEqual(s.march.respirationIntervention, "Needle decompression")
        XCTAssertTrue(s.interventions.contains { $0.kind == .needleDecompression })
    }

    func testInterventionDeduplication() {
        // Apply twice — should only get one intervention entry.
        let first = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Applying chest seal to the left chest.")
        )
        let second = extractor.apply(
            first,
            context: makeContext(sentence: "Re-checking chest seal placement.")
        )
        XCTAssertEqual(
            second.interventions.filter { $0.description == "Chest seal applied" }.count,
            1
        )
    }

    // MARK: - Respiratory rate inference

    func testNormalRespirationRate() {
        // RR 18 → "normal", and vitals.rr should be set
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Respiratory rate looks about 18.")
        )
        XCTAssertEqual(s.vitals.rr, 18)
        XCTAssertEqual(s.march.respirationStatus, "normal")
    }

    func testTachypneicRespirationRate() {
        // RR 28 → tachypneic
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Respiratory rate is 28.")
        )
        XCTAssertEqual(s.vitals.rr, 28)
        XCTAssertEqual(s.march.respirationStatus, "tachypneic")
    }

    func testBradypneicRespirationRate() {
        // RR 8 → bradypneic
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Respiratory rate 8.")
        )
        XCTAssertEqual(s.vitals.rr, 8)
        XCTAssertEqual(s.march.respirationStatus, "bradypneic")
    }

    func testRROverridesPneumothoraxStatus() {
        // Python: if status is None OR status == "possible pneumothorax",
        // the RR-derived status takes over.
        var seed = emptyState()
        seed.march.respirationStatus = "possible pneumothorax"
        let s = extractor.apply(
            seed,
            context: makeContext(sentence: "Respiratory rate is 18.")
        )
        XCTAssertEqual(s.march.respirationStatus, "normal")
    }

    func testRRDoesNotOverrideExistingNonPneumoStatus() {
        // If respirationStatus is e.g. "labored", RR-derived must NOT clobber it.
        var seed = emptyState()
        seed.march.respirationStatus = "labored"
        let s = extractor.apply(
            seed,
            context: makeContext(sentence: "Respiratory rate is 18.")
        )
        XCTAssertEqual(s.march.respirationStatus, "labored")
        XCTAssertEqual(s.vitals.rr, 18)
    }

    // MARK: - Negation flag suppresses positive findings

    func testIsNegatedSuppressesBreathSounds() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No bilateral breath sounds heard.",
                isNegated: true
            )
        )
        XCTAssertNil(s.march.breathSounds)
    }

    func testIsNegatedSuppressesChestSeal() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No chest seal needed.",
                isNegated: true
            )
        )
        XCTAssertNil(s.march.respirationIntervention)
        XCTAssertTrue(s.interventions.isEmpty)
    }

    // MARK: - Scenario-level mirrors

    func testScenario1NoPneumothorax() throws {
        // Mirrors Python test_scenario1_no_pneumothorax — full scenario fed
        // sentence-by-sentence, must NOT yield "possible pneumothorax".
        let scenario = try loadScenario("scenario_1_gsw_thigh.txt")
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
        XCTAssertNotEqual(s.march.respirationStatus, "possible pneumothorax")
    }

    func testScenario1BreathSoundsBilateralEqual() throws {
        let scenario = try loadScenario("scenario_1_gsw_thigh.txt")
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
        XCTAssertEqual(s.march.breathSounds, "bilateral equal")
    }

    // MARK: - Resource loader

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
