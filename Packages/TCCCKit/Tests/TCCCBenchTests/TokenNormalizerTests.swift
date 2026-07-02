import XCTest
@testable import TCCCBench

final class TokenNormalizerTests: XCTestCase {
    func testLowercasesAndStripsPunctuation() {
        XCTAssertEqual(
            TokenNormalizer.tokens("SpO2 is dropping, we're at 88%."),
            ["spo2", "is", "dropping", "were", "at", "88"]
        )
    }

    func testNumberWordsFoldToDigits() {
        XCTAssertEqual(
            TokenNormalizer.tokens("Eight-Seven-Three-Four, Niner-One-Two-Zero"),
            ["8", "7", "3", "4", "9", "1", "2", "0"]
        )
    }

    func testLongDigitStringsSplitToSingleDigits() {
        // "8734 9120" spoken as digits vs recognized as one number must align.
        XCTAssertEqual(TokenNormalizer.tokens("8734 9120"), ["8", "7", "3", "4", "9", "1", "2", "0"])
        XCTAssertEqual(TokenNormalizer.tokens("135"), ["1", "3", "5"])
        XCTAssertEqual(TokenNormalizer.tokens("88 over 60"), ["88", "over", "60"])
    }

    func testTensUnitsCombine() {
        // "thirty two" ≡ "32"
        XCTAssertEqual(TokenNormalizer.tokens("maybe thirty two a minute"), ["maybe", "32", "a", "minute"])
        XCTAssertEqual(TokenNormalizer.tokens("maybe 32 a minute"), ["maybe", "32", "a", "minute"])
    }

    func testExtraFoldsMergeRuns() {
        XCTAssertEqual(
            TokenNormalizer.tokens("gave one gram of T X A now", extraFolds: [["t", "x", "a", "txa"]]),
            ["gave", "1", "gram", "of", "txa", "now"]
        )
    }

    func testDecimalNumbersSurviveAsDigitRuns() {
        // "44.50" — dot is stripped; both ref and hyp normalize identically.
        XCTAssertEqual(TokenNormalizer.tokens("Frequency is 44.50"), ["frequency", "is", "4", "4", "5", "0"])
    }
}
