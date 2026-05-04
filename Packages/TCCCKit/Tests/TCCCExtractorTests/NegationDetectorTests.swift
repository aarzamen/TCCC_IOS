// NegationDetectorTests
//
// Parity tests for `NegationDetector` against `has_negated_finding` from
// /Users/ama/TCCC_FEB_2026/src/state.py:24–35.
//
// Most assertions are ported verbatim from
// /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py:TestHasNegatedFinding.

import XCTest
@testable import TCCCExtractor

final class NegationDetectorTests: XCTestCase {

    private let n = NegationDetector()

    // MARK: - Direct ports of TestHasNegatedFinding (test_state_negation.py:22–50)

    func testNoSignsOf() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No signs of pneumothorax.", finding: "pneumothorax"))
    }

    func testNegativeFor() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "Negative for pneumothorax.", finding: "pneumothorax"))
    }

    func testDenies() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "Patient denies chest pain.", finding: "chest pain"))
    }

    func testNoBare() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No pneumothorax.", finding: "pneumothorax"))
    }

    func testNothing() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "Nothing urgent here.", finding: "urgent"))
    }

    func testNot() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "This is not urgent.", finding: "urgent"))
    }

    func testPositiveStatementNotNegated() {
        XCTAssertFalse(n.hasNegatedFinding(
            in: "Possible pneumothorax detected.", finding: "pneumothorax"))
        XCTAssertFalse(n.hasNegatedFinding(
            in: "This is urgent.", finding: "urgent"))
    }

    func testNoChestTrauma() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No chest trauma.", finding: "chest trauma"))
    }

    func testNoTension() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No tension here.", finding: "tension"))
    }

    // MARK: - Additional negation prefix coverage

    func testWithoutPrefix() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "Patient is without distress.", finding: "distress"))
    }

    func testNoEvidenceOfPrefix() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No evidence of internal bleeding.", finding: "internal bleeding"))
    }

    func testAbsentPrefix() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "Radial pulse absent left.", finding: "left", window: 2))
    }

    // MARK: - Window enforcement
    //
    // Default window is 5 words between negation prefix and finding.

    func testWithinDefaultWindow() {
        // 4 intervening words between "no" and "pneumothorax"
        XCTAssertTrue(n.hasNegatedFinding(
            in: "no overt sign of obvious tension pneumothorax.",
            finding: "pneumothorax"))
    }

    func testBeyondDefaultWindow() {
        // 7 intervening words; outside default window of 5.
        XCTAssertFalse(n.hasNegatedFinding(
            in: "no overt sign of obvious tension or possible severe pneumothorax.",
            finding: "pneumothorax"))
    }

    func testCustomWindowExpands() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "no overt sign of obvious tension or possible severe pneumothorax.",
            finding: "pneumothorax",
            window: 10))
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveFinding() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No Pneumothorax.", finding: "PNEUMOTHORAX"))
    }

    func testCaseInsensitivePrefix() {
        XCTAssertTrue(n.hasNegatedFinding(
            in: "NO SIGNS OF pneumothorax.", finding: "pneumothorax"))
    }

    // MARK: - Word-boundary regression

    func testKnowsWordBoundaryOnNo() {
        // "snoring" contains "no" but not as a word — must not trigger.
        XCTAssertFalse(n.hasNegatedFinding(
            in: "snoring patient with audible breath sounds.",
            finding: "patient"))
    }

    func testKnowsWordBoundaryOnNot() {
        // "notably" contains "not" as substring; word-boundary keeps us safe.
        XCTAssertFalse(n.hasNegatedFinding(
            in: "notably alert urgent casualty.", finding: "urgent"))
    }

    // MARK: - Special characters in finding (regex escape)

    func testFindingWithRegexMetacharsIsLiteral() {
        // Test that the finding is escaped properly.
        XCTAssertTrue(n.hasNegatedFinding(
            in: "No 3.5cm wound found.", finding: "3.5cm"))
    }

    // MARK: - sentenceHasNegationMarker (looser sentence-level check)

    func testSentenceMarkerDetectsNoSignsOf() {
        XCTAssertTrue(n.sentenceHasNegationMarker("No signs of pneumothorax."))
    }

    func testSentenceMarkerDetectsBareNo() {
        XCTAssertTrue(n.sentenceHasNegationMarker("No bleeding observed."))
    }

    func testSentenceMarkerDetectsNothing() {
        XCTAssertTrue(n.sentenceHasNegationMarker("Nothing urgent here."))
    }

    func testSentenceMarkerDetectsDenies() {
        XCTAssertTrue(n.sentenceHasNegationMarker("Patient denies pain."))
    }

    func testSentenceMarkerDoesNotMisfireOnPositive() {
        XCTAssertFalse(n.sentenceHasNegationMarker("Patient is alert and oriented."))
    }

    func testSentenceMarkerDoesNotMisfireOnSnoring() {
        // "snoring" contains "no" only as a substring; \bno\b must skip.
        XCTAssertFalse(n.sentenceHasNegationMarker("snoring patient."))
    }
}
