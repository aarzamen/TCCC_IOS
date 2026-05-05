// MGRSTests
//
// Unit tests for the in-house MGRS encoder. Reference fixtures generated
// via Python's `hobuinc/mgrs` (NGA GeoTrans wrapper) — see
// `MGRS_VALIDATION.md` at repo root for methodology and the full diff
// table. All fixtures here assert FULL 15-character MGRS strings at
// 1m precision: zone(2)+band(1)+square(2)+easting(5)+northing(5).
//
// Coverage:
//   - 4 canonical fixtures (Bagram / DC / Origin / Bergen)
//   - Equatorial crossings + zone-1 antimeridian
//   - UTM zone boundaries (±6°, ±12°, ±174°, ±180°)
//   - Latitude band boundaries (8°N, 32°N, 72°N)
//   - 32V Norway exception (5 spans of 56-64°N × 0-12°E)
//   - Svalbard 31X / 33X / 35X / 37X (band X stretching)
//   - Southern hemisphere (Sydney, Cape Town, Buenos Aires, Auckland,
//     Antarctic peninsula, Tonga)
//   - Wide longitude span (Tokyo, Anchorage, Reykjavik, San Francisco)

import XCTest
@testable import TCCCDomain

final class MGRSTests: XCTestCase {

    // MARK: - Canonical fixtures (full-string assertions)

    func testBagram() {
        let m = MGRS.from(latitude: 34.5267, longitude: 69.1729)
        XCTAssertEqual(m, "42SWD1586720571",
                       "Bagram default-GPS fixture should round-trip exact GeoTrans output.")
    }

    func testWashingtonDC() {
        let m = MGRS.from(latitude: 38.8977, longitude: -77.0365)
        XCTAssertEqual(m, "18SUJ2339407395")
    }

    func testOrigin() {
        // Just NE of (0,0) — exercises 100km-square boundary near origin.
        let m = MGRS.from(latitude: 0.0001, longitude: 0.0001)
        XCTAssertEqual(m, "31NAA6603200011")
    }

    func testNorwayException() {
        // Bergen 60.39N 5.32E — without the Norway exception this would
        // fall in zone 31; the exception bumps it to 32V.
        let m = MGRS.from(latitude: 60.39, longitude: 5.32)
        XCTAssertEqual(m, "32VKN9723000510")
    }

    // MARK: - Zone-padding (zones 1–9 must zero-pad to two digits)

    func testZoneOnePaddingAtAntimeridian() {
        // 45N just east of -180 → zone 1, must be "01TBK…"
        let m = MGRS.from(latitude: 45.0, longitude: -179.9999)
        XCTAssertEqual(m, "01TBK6356187329")
    }

    func testSingleDigitZonePaddingAnchorage() {
        // Zone 6 — must render as "06V…", not "6V…"
        let m = MGRS.from(latitude: 61.2181, longitude: -149.9003)
        XCTAssertEqual(m, "06VUN4424790536")
    }

    // MARK: - Equatorial / hemispheric

    func testEquatorJustNorth() {
        let m = MGRS.from(latitude: 0.5, longitude: 30.0)
        XCTAssertEqual(m, "36NSF6603455341")
    }

    func testEquatorJustSouth() {
        let m = MGRS.from(latitude: -0.5, longitude: 30.0)
        XCTAssertEqual(m, "36MSE6603444658")
    }

    func testEquatorAtZoneOneBoundary() {
        let m = MGRS.from(latitude: 0.5, longitude: -179.0)
        XCTAssertEqual(m, "01NBA7741255298")
    }

    // MARK: - UTM zone boundaries (every 6°)

    func testJustEastOfSixDegMeridian() {
        let m = MGRS.from(latitude: 45.0, longitude: 6.0001)
        XCTAssertEqual(m, "32TKQ6356187329")
    }

    func testJustWestOfSixDegMeridian() {
        let m = MGRS.from(latitude: 45.0, longitude: 5.9999)
        XCTAssertEqual(m, "31TGK3643887329")
    }

    func testJustEastOfTwelveDegMeridian() {
        let m = MGRS.from(latitude: 45.0, longitude: 12.0001)
        XCTAssertEqual(m, "33TTK6356187329")
    }

    func testJustWestOfOneSeventyFourDegMeridian() {
        let m = MGRS.from(latitude: -45.0, longitude: 173.9999)
        XCTAssertEqual(m, "59GQL3643812670")
    }

    // MARK: - Latitude band boundaries

    func testEightDegNorthJustIntoBandP() {
        let m = MGRS.from(latitude: 8.001, longitude: 30.0)
        XCTAssertEqual(m, "36PSP6925685614")
    }

    func test7Point99DegNorthStillInBandN() {
        let m = MGRS.from(latitude: 7.99, longitude: 30.0)
        XCTAssertEqual(m, "36NSP6924884396")
    }

    func test32DegNorthBandRSBoundary() {
        let mR = MGRS.from(latitude: 31.99, longitude: 30.0)
        let mS = MGRS.from(latitude: 32.01, longitude: 30.0)
        XCTAssertEqual(mR, "36RTA1654543260")
        XCTAssertEqual(mS, "36STA1660745479")
    }

    func test72DegNorthBandWBoundary() {
        // Just below 72°N is band W (still zone 32 — Svalbard kicks in at 72.0).
        let m = MGRS.from(latitude: 71.99, longitude: 10.0)
        XCTAssertEqual(m, "32WNE3450788103")
    }

    // MARK: - 32V Norway exception (5 spans)

    func testNorway32VSouthwestCorner() {
        let m = MGRS.from(latitude: 56.001, longitude: 3.001)
        XCTAssertEqual(m, "32VJH2612122441")
    }

    func testNorway32VNortheastCorner() {
        let m = MGRS.from(latitude: 63.999, longitude: 11.999)
        XCTAssertEqual(m, "32VPS4665100353")
    }

    func testNorway32VMidEast() {
        let m = MGRS.from(latitude: 60.0, longitude: 9.0)
        XCTAssertEqual(m, "32VNM0000051411")
    }

    func testNorway32VBergenExact() {
        // 60.0N 5.0E from RESEARCH_MGRS.md fixtures list.
        let m = MGRS.from(latitude: 60.0, longitude: 5.0)
        XCTAssertEqual(m, "32VKM7697958157")
    }

    func testPreNorwayExceptionStillZone31() {
        // 55.99N is below the exception's 56°N floor — zone 31U not 32V.
        let m = MGRS.from(latitude: 55.99, longitude: 5.0)
        XCTAssertEqual(m, "31UFC2475806771")
    }

    func testPostNorwayExceptionStillZone31() {
        // 64.01N is above the exception's 64°N ceiling — zone 31W not 32V.
        let m = MGRS.from(latitude: 64.01, longitude: 5.0)
        XCTAssertEqual(m, "31WEL9777799662")
    }

    // MARK: - Svalbard band X (zones 31, 33, 35, 37 are stretched; 32/34/36 skipped)

    func testSvalbard31X() {
        // 73N 5E falls in stretched zone 31X (lon 0-9).
        let m = MGRS.from(latitude: 73.0, longitude: 5.0)
        XCTAssertEqual(m, "31XEB6525601569")
    }

    func testSvalbard33X() {
        // 78N 15E falls in zone 33X (lon 9-21).
        let m = MGRS.from(latitude: 78.0, longitude: 15.0)
        XCTAssertEqual(m, "33XWG0000058369")
    }

    func testSvalbard35X() {
        // 80N 25E falls in zone 35X (lon 21-33).
        let m = MGRS.from(latitude: 80.0, longitude: 25.0)
        XCTAssertEqual(m, "35XMJ6123582252")
    }

    func testSvalbard37X() {
        // 82N 35E falls in zone 37X (lon 33-42).
        let m = MGRS.from(latitude: 82.0, longitude: 35.0)
        XCTAssertEqual(m, "37XDM3789806976")
    }

    // MARK: - Southern hemisphere

    func testSydneyAustralia() {
        let m = MGRS.from(latitude: -33.8688, longitude: 151.2093)
        XCTAssertEqual(m, "56HLH3436850948")
    }

    func testCapeTown() {
        let m = MGRS.from(latitude: -33.9249, longitude: 18.4241)
        XCTAssertEqual(m, "34HBH6188143182")
    }

    func testBuenosAires() {
        let m = MGRS.from(latitude: -34.6037, longitude: -58.3816)
        XCTAssertEqual(m, "21HUB7331770036")
    }

    func testAucklandNZ() {
        let m = MGRS.from(latitude: -36.85, longitude: 174.76)
        XCTAssertEqual(m, "60HUE0028819425")
    }

    func testAntarcticPeninsulaBandC() {
        // -75°S is band C — exercises low-lat band table entry.
        let m = MGRS.from(latitude: -75.0, longitude: -60.0)
        XCTAssertEqual(m, "21CVS1336274201")
    }

    // MARK: - Other notable points

    func testSanFrancisco() {
        let m = MGRS.from(latitude: 37.7749, longitude: -122.4194)
        XCTAssertEqual(m, "10SEG5113080998")
    }

    func testKhulaniSqBaghdad() {
        let m = MGRS.from(latitude: 33.32, longitude: 44.42)
        XCTAssertEqual(m, "38SMB4601486913")
    }

    func testTokyo() {
        let m = MGRS.from(latitude: 35.6762, longitude: 139.6503)
        XCTAssertEqual(m, "54SUE7785548874")
    }

    func testReykjavik() {
        let m = MGRS.from(latitude: 64.1466, longitude: -21.9426)
        XCTAssertEqual(m, "27WVM5413813689")
    }

    func testHavanaCuba() {
        let m = MGRS.from(latitude: 23.13, longitude: -82.36)
        XCTAssertEqual(m, "17QLF6074958560")
    }

    func testGreenwichLondon() {
        let m = MGRS.from(latitude: 51.5, longitude: 0.0)
        XCTAssertEqual(m, "31UBT9178309696")
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

    // MARK: - Formatting

    func testFormattingInsertsSpaces() {
        // Two-digit zone — "42S WD 12345 67890"
        let spaced = MGRS.formatted("42SWD1234567890")
        XCTAssertEqual(spaced, "42S WD 12345 67890")
    }

    func testFormattingPreservesLeadingZero() {
        // Zero-padded zone must round-trip through the spacer.
        let spaced = MGRS.formatted("06VUN4424790536")
        XCTAssertEqual(spaced, "06V UN 44247 90536")
    }

    func testFormattedFromCoordinate() {
        guard let spaced = MGRS.formatted(latitude: 34.5267, longitude: 69.1729) else {
            XCTFail("Expected non-nil MGRS for Bagram")
            return
        }
        XCTAssertEqual(spaced, "42S WD 15867 20571")
    }

    func testFormattedFromCoordinateZonePadding() {
        // Anchorage — zone 6, should format as "06V UN ..."
        guard let spaced = MGRS.formatted(latitude: 61.2181, longitude: -149.9003) else {
            XCTFail("Expected non-nil MGRS for Anchorage")
            return
        }
        XCTAssertEqual(spaced, "06V UN 44247 90536")
    }
}
