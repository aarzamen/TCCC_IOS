import XCTest
@testable import TCCCBench

final class WERScorerTests: XCTestCase {
    func testIdenticalIsZero() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "b", "c"])
        XCTAssertEqual(r.errorCount, 0)
        XCTAssertEqual(r.wer, 0.0)
    }

    func testSingleSubstitution() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "x", "c"])
        XCTAssertEqual(r.substitutions, 1)
        XCTAssertEqual(r.insertions, 0)
        XCTAssertEqual(r.deletions, 0)
        XCTAssertEqual(r.wer, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testInsertionAndDeletion() {
        XCTAssertEqual(WERScorer.score(reference: ["a", "b"], hypothesis: ["a", "x", "b"]).insertions, 1)
        XCTAssertEqual(WERScorer.score(reference: ["a", "b", "c"], hypothesis: ["a", "c"]).deletions, 1)
    }

    func testEmptyHypothesisIsAllDeletions() {
        let r = WERScorer.score(reference: ["a", "b", "c"], hypothesis: [])
        XCTAssertEqual(r.deletions, 3)
        XCTAssertEqual(r.wer, 1.0)
    }

    func testEmptyReferenceCountsInsertionsWithWerOneWhenHypNonEmpty() {
        let r = WERScorer.score(reference: [], hypothesis: ["a"])
        XCTAssertEqual(r.insertions, 1)
        XCTAssertEqual(r.wer, 1.0)
        XCTAssertEqual(WERScorer.score(reference: [], hypothesis: []).wer, 0.0)
    }
}
