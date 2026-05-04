// FractureExtractorTests
//
// Mirrors the Python regression suite for fracture findings:
//   - /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py (test_scenario4_*).
//   - The fracture/splinting behaviour from `_extract_fractures` in
//     /Users/ama/TCCC_FEB_2026/src/state.py:857–896.
//
// Constructs an `ExtractionContext` directly per sentence and applies the
// extractor — no engine dependency.

import XCTest
@testable import TCCCDomain
@testable import TCCCExtractor

final class FractureExtractorTests: XCTestCase {

    private let extractor = FractureExtractor()
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

    // MARK: - Fracture location detection

    func testRightFemurFracture() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "This looks like a mid-shaft right femur fracture.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("right femur fracture") })
    }

    func testLeftFemurFracture() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Left femur fracture, no open wound.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("left femur fracture") })
    }

    func testThighFractureCategorisedAsFemur() {
        // The femur/thigh/hip rule maps everything to "femur fracture".
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Right thigh fracture present.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("right femur fracture") })
    }

    func testLowerLegFractureFromTibia() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Right tibia fracture identified.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("right lower leg fracture") })
    }

    func testAnkleFractureMapsToLowerLeg() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Left ankle fracture suspected.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("left lower leg fracture") })
    }

    func testArmFractureFromRadius() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Right radius fracture observed.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("right arm fracture") })
    }

    func testWristFractureMapsToArm() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Left wrist fracture confirmed.")
        )
        XCTAssertTrue(s.injuries.contains { $0.lowercased().contains("left arm fracture") })
    }

    func testNoFractureMentionedNoExtraction() {
        // The fracture top-level pattern must match before any location is checked.
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Patient has a femur. Anatomy is intact.")
        )
        XCTAssertTrue(s.injuries.isEmpty)
        XCTAssertNil(s.march.hemorrhageLocation)
    }

    // MARK: - Femur fracture seeds hemorrhage location

    func testFemurFractureSeedsHemorrhageLocationWhenEmpty() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Right femur fracture identified.")
        )
        XCTAssertNotNil(s.march.hemorrhageLocation)
        XCTAssertTrue(s.march.hemorrhageLocation!.lowercased().contains("femur"))
    }

    func testFemurFractureAnnotatesExistingHemorrhageLocation() {
        var seed = emptyState()
        seed.march.hemorrhageLocation = "right thigh"
        let s = extractor.apply(
            seed,
            context: makeContext(sentence: "Right femur fracture identified.")
        )
        XCTAssertEqual(s.march.hemorrhageLocation, "right thigh (femur fracture)")
    }

    func testFemurFractureDoesNotDoubleAnnotate() {
        // Pre-existing location already mentions "femur" — Python skips annotation.
        var seed = emptyState()
        seed.march.hemorrhageLocation = "right thigh (femur fracture)"
        let s = extractor.apply(
            seed,
            context: makeContext(sentence: "Right femur fracture confirmed.")
        )
        XCTAssertEqual(s.march.hemorrhageLocation, "right thigh (femur fracture)")
    }

    // MARK: - Splinting

    func testSagerTractionSplint() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Traction splint, Sager, applied to the right lower extremity.")
        )
        XCTAssertTrue(s.interventions.contains { $0.description == "Traction splint (Sager)" })
        XCTAssertTrue(s.interventions.contains { $0.kind == .splint })
    }

    func testSamSplint() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "SAM splint applied to the left arm.")
        )
        XCTAssertTrue(s.interventions.contains { $0.description == "SAM splint" })
    }

    func testGenericSplintDescriptor() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Splint applied to the right lower extremity.")
        )
        XCTAssertTrue(s.interventions.contains { $0.description == "Splint applied" })
    }

    func testImmobiliseTriggersSplint() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Immobilizing the right leg.")
        )
        XCTAssertTrue(s.interventions.contains { $0.description == "Splint applied" })
    }

    func testSplintDeduplicationAcrossSentences() {
        let first = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Sager applied to the right lower extremity.")
        )
        let second = extractor.apply(
            first,
            context: makeContext(sentence: "Re-checking traction splint placement.")
        )
        XCTAssertEqual(
            second.interventions.filter { $0.description == "Traction splint (Sager)" }.count,
            1
        )
    }

    // MARK: - Negation

    func testIsNegatedSuppressesFracture() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No femur fracture identified.",
                isNegated: true
            )
        )
        XCTAssertTrue(s.injuries.isEmpty)
        XCTAssertNil(s.march.hemorrhageLocation)
    }

    func testIsNegatedSuppressesSplint() {
        let s = extractor.apply(
            emptyState(),
            context: makeContext(
                sentence: "No splint needed.",
                isNegated: true
            )
        )
        XCTAssertTrue(s.interventions.isEmpty)
    }

    // MARK: - Injury deduplication

    func testInjuryDeduplicationAcrossSentences() {
        let first = extractor.apply(
            emptyState(),
            context: makeContext(sentence: "Right femur fracture identified.")
        )
        let second = extractor.apply(
            first,
            context: makeContext(sentence: "Confirming right femur fracture.")
        )
        XCTAssertEqual(
            second.injuries.filter { $0.lowercased().contains("right femur fracture") }.count,
            1
        )
    }

    // MARK: - Scenario-level mirrors

    func testScenario4FemurFractureInInjuries() throws {
        // Mirrors the spirit of the Python scenario_4 tests — splinting a
        // femur fracture should land in injuries and seed hemorrhage location.
        let scenario = try loadScenario("scenario_4_femur_fracture.txt")
        let s = applyExtractorToScenario(scenario)
        XCTAssertTrue(
            s.injuries.contains { $0.lowercased().contains("femur fracture") },
            "Expected a femur fracture entry in injuries: \(s.injuries)"
        )
        XCTAssertNotNil(s.march.hemorrhageLocation)
        XCTAssertTrue(s.march.hemorrhageLocation!.lowercased().contains("femur"))
    }

    func testScenario4SagerTractionSplintInterventionRecorded() throws {
        let scenario = try loadScenario("scenario_4_femur_fracture.txt")
        let s = applyExtractorToScenario(scenario)
        XCTAssertTrue(
            s.interventions.contains { $0.description == "Traction splint (Sager)" },
            "Expected Traction splint (Sager) in interventions: \(s.interventions.map(\.description))"
        )
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
