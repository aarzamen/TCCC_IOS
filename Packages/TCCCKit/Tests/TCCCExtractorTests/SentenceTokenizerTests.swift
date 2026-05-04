// SentenceTokenizerTests
//
// Parity tests for `SentenceTokenizer` against the Python regex
// `re.split(r"(?<=[.!?])\s+|\n+", text)` from
// /Users/ama/TCCC_FEB_2026/src/state.py:500.

import XCTest
@testable import TCCCExtractor

final class SentenceTokenizerTests: XCTestCase {

    private let t = SentenceTokenizer()

    // MARK: - Empty / trivial

    func testEmptyStringReturnsEmptyArray() {
        XCTAssertEqual(t.tokenize(""), [])
    }

    func testWhitespaceOnlyReturnsEmptyArray() {
        XCTAssertEqual(t.tokenize("   \n\n  \t  "), [])
    }

    func testSingleSentenceNoPunctuation() {
        XCTAssertEqual(t.tokenize("airway is patent"), ["airway is patent"])
    }

    func testSingleSentenceWithPeriod() {
        XCTAssertEqual(t.tokenize("Airway is patent."), ["Airway is patent."])
    }

    // MARK: - Period / exclamation / question splits

    func testTwoSentencesPeriod() {
        XCTAssertEqual(
            t.tokenize("Airway is patent. Breathing normal."),
            ["Airway is patent.", "Breathing normal."])
    }

    func testTwoSentencesExclamation() {
        XCTAssertEqual(
            t.tokenize("Corpsman up! He fell hard."),
            ["Corpsman up!", "He fell hard."])
    }

    func testTwoSentencesQuestion() {
        XCTAssertEqual(
            t.tokenize("Are you with me? Patient is alert."),
            ["Are you with me?", "Patient is alert."])
    }

    func testMixedTerminators() {
        XCTAssertEqual(
            t.tokenize("Hey! Are you okay? Let me check you."),
            ["Hey!", "Are you okay?", "Let me check you."])
    }

    // MARK: - Newlines

    func testNewlineOnlySplit() {
        XCTAssertEqual(
            t.tokenize("Airway patent\nBreathing normal"),
            ["Airway patent", "Breathing normal"])
    }

    func testMultipleNewlinesSplit() {
        XCTAssertEqual(
            t.tokenize("First\n\n\nSecond"),
            ["First", "Second"])
    }

    func testNewlineAfterPunctuation() {
        XCTAssertEqual(
            t.tokenize("First.\nSecond."),
            ["First.", "Second."])
    }

    // MARK: - No-split cases

    func testNoSpaceAfterPunctuationDoesNotSplit() {
        // Python regex requires whitespace AFTER punctuation. "1.5cm" stays whole.
        XCTAssertEqual(
            t.tokenize("Wound is 3.5cm long."),
            ["Wound is 3.5cm long."])
    }

    func testNumericDecimalNotSplit() {
        XCTAssertEqual(
            t.tokenize("Approximately 3.5 cm laceration."),
            ["Approximately 3.5 cm laceration."])
    }

    // MARK: - Medical abbreviations
    //
    // Note: Python's regex does NOT special-case "Sgt.", "Dr.", "Lt." — any
    // period followed by whitespace splits. We mirror Python verbatim, so
    // these abbreviations DO produce extra splits. Documenting the behavior
    // so consumers don't expect smarter tokenisation than the Python source.

    func testMedicalAbbreviationDrSplits() {
        XCTAssertEqual(
            t.tokenize("Dr. Smith is on call."),
            ["Dr.", "Smith is on call."])
    }

    func testRankAbbreviationSgtSplits() {
        XCTAssertEqual(
            t.tokenize("Sgt. Jones is the casualty."),
            ["Sgt.", "Jones is the casualty."])
    }

    func testRankAbbreviationLtSplits() {
        XCTAssertEqual(
            t.tokenize("Lt. Smith is unresponsive."),
            ["Lt.", "Smith is unresponsive."])
    }

    // MARK: - Trim + filter behaviour

    func testTrimsWhitespaceAroundSentences() {
        XCTAssertEqual(
            t.tokenize("   Airway is patent.   Breathing normal.   "),
            ["Airway is patent.", "Breathing normal."])
    }

    func testFiltersEmptyFragments() {
        XCTAssertEqual(
            t.tokenize("First.\n\n\n   \n\nSecond."),
            ["First.", "Second."])
    }

    // MARK: - Scenario fixtures
    //
    // These regression-test the engine's Phase-1 split against the bundled
    // text fixtures. We assert sentence COUNT matches Python output (captured
    // by running the Python regex against each scenario file).

    func testScenario1SentenceCount() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        // Python `re.split(r"(?<=[.!?])\s+|\n+", text)` then strip+filter
        // yields 19 sentences for scenario 1.
        XCTAssertEqual(t.tokenize(raw).count, 19)
    }

    func testScenario2SentenceCount() throws {
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        XCTAssertEqual(t.tokenize(raw).count, 23)
    }

    func testScenario3SentenceCount() throws {
        let raw = try loadScenario("scenario_3_mre_laceration.txt")
        XCTAssertEqual(t.tokenize(raw).count, 20)
    }

    func testScenario4SentenceCount() throws {
        let raw = try loadScenario("scenario_4_femur_fracture.txt")
        XCTAssertEqual(t.tokenize(raw).count, 41)
    }

    func testScenario1FirstSentenceContent() throws {
        let raw = try loadScenario("scenario_1_gsw_thigh.txt")
        let sentences = t.tokenize(raw)
        XCTAssertTrue(sentences.first?.starts(with: "Alright") ?? false,
                      "Expected first sentence to start with 'Alright', got: \(sentences.first ?? "nil")")
    }

    func testScenario2FirstSentenceContent() throws {
        let raw = try loadScenario("scenario_2_blast_multi.txt")
        let sentences = t.tokenize(raw)
        XCTAssertEqual(
            sentences.first,
            "We've got two casualties from an IED blast.")
    }

    // MARK: - Helpers

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
