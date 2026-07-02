import XCTest
@testable import TCCCBench

final class ScorerTests: XCTestCase {
    func testKeywordRecallMultiTokenPhrase() {
        let tokens = TokenNormalizer.tokens("moving to a needle decompression right side")
        let r = KeywordRecallScorer.score(
            keywords: ["needle decompression", "chest seal"],
            transcriptTokens: tokens
        )
        XCTAssertEqual(r.hits, ["needle decompression"])
        XCTAssertEqual(r.misses, ["chest seal"])
        XCTAssertEqual(r.recall, 0.5, accuracy: 1e-9)
    }

    func testKeywordRecallNormalizesKeywordsToo() {
        // Keyword "8734" ≡ spoken "eight seven three four".
        let tokens = TokenNormalizer.tokens("grid eight seven three four confirmed")
        let r = KeywordRecallScorer.score(keywords: ["8734"], transcriptTokens: tokens)
        XCTAssertEqual(r.hits, ["8734"])
    }

    func testExtractionScorerModes() {
        let expectations = [
            FieldExpectation(key: "hr", expected: "135", mode: .exact),
            FieldExpectation(key: "interventions", expected: "chest seal", mode: .contains),
            FieldExpectation(key: "rr", expected: "32", mode: .exact),
        ]
        let actual = ["hr": "135", "interventions": "vented chest seal; needle decompression"]
        let score = ExtractionScorer.score(expectations: expectations, actual: actual)
        XCTAssertEqual(score.passedCount, 2)
        XCTAssertEqual(score.recall, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(score.fields.first(where: { $0.key == "rr" })?.passed, false)
        XCTAssertNil(score.fields.first(where: { $0.key == "rr" })?.actual)
    }
}
