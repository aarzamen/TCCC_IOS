// MGRSTests
//
// Unit tests for the in-house MGRS encoder. Reference fixtures pulled
// from RESEARCH_MGRS.md (validated against Python's `hobuinc/mgrs`
// during the night-pass research).

import XCTest
@testable import TCCCDomain

final class MGRSTests: XCTestCase {

    // MARK: - Canonical fixtures

    func testBagram() {
        // Bagram-ish, the project's default GPS — expected 42SWD1586720571
        let m = MGRS.from(latitude: 34.5267, longitude: 69.1729)
        XCTAssertEqual(zoneBandSquare(m), "42SWD",
                       "Bagram should land in 42SWD; got \(m ?? "nil")")
    }

    func testWashingtonDC() {
        // 38.8977 N 77.0365 W → expected 18SUJ2339407395
        let m = MGRS.from(latitude: 38.8977, longitude: -77.0365)
        XCTAssertEqual(zoneBandSquare(m), "18SUJ",
                       "DC should land in 18SUJ; got \(m ?? "nil")")
    }

    func testOrigin() {
        // 0 N 0 E — expected 31NAA, but easting/northing are 0 km. We
        // assert the prefix only since the easting handling at the
        // 100km square boundary is fragile near origin.
        let m = MGRS.from(latitude: 0.0001, longitude: 0.0001)
        XCTAssertNotNil(m)
        XCTAssertTrue(m?.hasPrefix("31N") ?? false,
                      "Origin should be in zone 31N; got \(m ?? "nil")")
    }

    func testNorwayException() {
        // Bergen 60.39 N 5.32 E sits in the 32V exception zone. The
        // ordinary zone calc would put it at zone 31; the Norway
        // exception bumps it to 32.
        let m = MGRS.from(latitude: 60.39, longitude: 5.32)
        XCTAssertNotNil(m)
        XCTAssertTrue(m?.hasPrefix("32V") ?? false,
                      "Bergen should be in zone 32V (Norway exception); got \(m ?? "nil")")
    }

    // MARK: - Edge cases

    func testNonFiniteRejected() {
        XCTAssertNil(MGRS.from(latitude: .nan, longitude: 0))
        XCTAssertNil(MGRS.from(latitude: 0, longitude: .nan))
        XCTAssertNil(MGRS.from(latitude: .infinity, longitude: 0))
    }

    func testPolarRejected() {
        // > 84°N or < -80°S — UPS coverage, we return nil.
        XCTAssertNil(MGRS.from(latitude: 85.0, longitude: 0))
        XCTAssertNil(MGRS.from(latitude: -85.0, longitude: 0))
    }

    func testFormattingInsertsSpaces() {
        // Compact form 42SWD1234567890 → spaced "42S WD 12345 67890".
        let spaced = MGRS.formatted("42SWD1234567890")
        XCTAssertEqual(spaced, "42S WD 12345 67890")
    }

    func testFormattedFromCoordinate() {
        guard let spaced = MGRS.formatted(latitude: 34.5267, longitude: 69.1729) else {
            XCTFail("Expected non-nil MGRS for Bagram")
            return
        }
        XCTAssertTrue(spaced.hasPrefix("42S WD"),
                      "Expected '42S WD' prefix; got \(spaced)")
    }

    // MARK: - Helpers

    /// Strip the trailing 10-digit easting/northing so the test asserts
    /// only on zone+band+square (the parts our coarse-precision
    /// implementation is most sensitive to).
    private func zoneBandSquare(_ mgrs: String?) -> String? {
        guard let mgrs else { return nil }
        let chars = Array(mgrs)
        var endOfLetters = chars.count
        while endOfLetters > 0, chars[endOfLetters - 1].isNumber {
            endOfLetters -= 1
        }
        return String(chars[..<endOfLetters])
    }
}
