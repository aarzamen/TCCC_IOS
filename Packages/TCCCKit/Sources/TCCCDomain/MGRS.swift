// MGRS — Military Grid Reference System encoding.
//
// Forward-only WGS-84 → MGRS conversion in pure Swift / Foundation.
// Per night-pass A2 (2026-05-05).
//
// Why ours and not ngageoint/mgrs-ios: the upstream `mgrs-ios` library
// has UTM ↔ lat/lon expressions that exceed Swift 6's type-inference
// solver budget under strict-concurrency settings. We only need the
// forward direction (lat/lon → MGRS) for display, so a small focused
// implementation avoids the third-party churn.
//
// Coverage:
//   - UTM zones 1–60, latitude bands C–X (~80°S to 84°N).
//   - Norway/Svalbard zone exception (zone 32V extends west; 31X-37X
//     stretched to cover Svalbard).
//   - Polar regions (UPS) NOT covered. Returns `nil` for |lat| > 84.
//   - 100km grid square letter pairs per the AA / AL scheme.
//   - 5-digit easting/northing precision (1m).
//
// References (extracted into RESEARCH_MGRS.md):
//   - NGA Geospatial Sciences Division "TM 8358.1" UTM/MGRS technical
//     manual.
//   - https://en.wikipedia.org/wiki/Military_Grid_Reference_System
//   - GeographicLib (Charles Karney) — used to validate test fixtures.

import Foundation

public enum MGRS {

    /// Forward conversion. Returns a compact MGRS string at 5-digit
    /// precision (1m), e.g. `"42SWD1586720571"`. Returns nil if the
    /// coordinate is outside coverage (UPS polar zones, NaN inputs).
    public static func from(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite,
              latitude >= -80.0, latitude <= 84.0 else {
            return nil
        }

        // Normalise longitude into (-180, 180]
        var lon = longitude
        while lon > 180 { lon -= 360 }
        while lon <= -180 { lon += 360 }

        let zone = utmZone(latitude: latitude, longitude: lon)
        guard let band = latitudeBand(latitude: latitude) else { return nil }

        let centralMeridian = Double((zone - 1) * 6 - 180 + 3)
        let utm = latLonToUTM(
            latitude: latitude,
            longitude: lon,
            centralMeridianDeg: centralMeridian
        )

        // 100km grid square letters per the AA/AL alternating scheme.
        // Easting letters cycle A..H, J..N, P..Z (skip I and O) every
        // 100km, repeating every 8 zones in groups of 8 letters.
        // Northing letters cycle A..H, J..N, P..V (skip I and O) every
        // 100km, repeating every 2 million metres, with an offset that
        // alternates between odd and even zones.
        let eastingIdx = Int((utm.easting / 100000.0).rounded(.down)) - 1
        let northingMetres = utm.northing.truncatingRemainder(dividingBy: 2_000_000)
        let northingIdx = Int((northingMetres / 100000.0).rounded(.down))
        let eastingLetter = eastingLetter(zone: zone, idx: eastingIdx)
        let northingLetter = northingLetter(zone: zone, idx: northingIdx)
        guard let eastingLetter, let northingLetter else { return nil }

        let eastingDigits = Int(utm.easting.truncatingRemainder(dividingBy: 100000))
        let northingDigits = Int(utm.northing.truncatingRemainder(dividingBy: 100000))

        return String(
            format: "%d%@%@%@%05d%05d",
            zone, String(band), String(eastingLetter), String(northingLetter),
            eastingDigits, northingDigits
        )
    }

    /// Voice-readable form: zone-band, 100km square, easting, northing
    /// space-separated. e.g. `42S WD 12345 67890`.
    public static func formatted(latitude: Double, longitude: Double) -> String? {
        guard let raw = from(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return formatted(raw)
    }

    /// Insert spaces into a compact MGRS string.
    public static func formatted(_ compact: String) -> String {
        let chars = Array(compact)
        var endOfLetters = chars.count
        while endOfLetters > 0, chars[endOfLetters - 1].isNumber {
            endOfLetters -= 1
        }
        let digitCount = chars.count - endOfLetters
        guard digitCount > 0, digitCount % 2 == 0 else { return compact }
        let half = digitCount / 2
        let prefix = String(chars[..<endOfLetters])
        guard prefix.count >= 3 else { return compact }
        let prefixChars = Array(prefix)
        let zoneBand = String(prefixChars[..<(prefixChars.count - 2)])
        let square = String(prefixChars[(prefixChars.count - 2)...])
        let easting = String(chars[endOfLetters..<(endOfLetters + half)])
        let northing = String(chars[(endOfLetters + half)...])
        return "\(zoneBand) \(square) \(easting) \(northing)"
    }

    // MARK: - Internal: zone + band derivation

    private static func utmZone(latitude: Double, longitude: Double) -> Int {
        var zone = Int(floor((longitude + 180.0) / 6.0)) + 1
        // Norway exception: zone 32V extends from 3°E to 12°E.
        if latitude >= 56.0 && latitude < 64.0 && longitude >= 3.0 && longitude < 12.0 {
            zone = 32
        }
        // Svalbard exception: zones 31, 33, 35, 37 are stretched.
        if latitude >= 72.0 && latitude < 84.0 {
            if longitude >= 0.0 && longitude < 9.0 { zone = 31 }
            else if longitude >= 9.0 && longitude < 21.0 { zone = 33 }
            else if longitude >= 21.0 && longitude < 33.0 { zone = 35 }
            else if longitude >= 33.0 && longitude < 42.0 { zone = 37 }
        }
        return max(1, min(60, zone))
    }

    /// MGRS latitude band letter (C..X, skipping I and O). 8° per band
    /// from -80°S; X is the only 12° band (72°N to 84°N).
    private static func latitudeBand(latitude: Double) -> Character? {
        // C=-80, D=-72, E=-64, F=-56, G=-48, H=-40, J=-32, K=-24, L=-16,
        // M=-8, N=0, P=8, Q=16, R=24, S=32, T=40, U=48, V=56, W=64,
        // X=72..84.
        let bands: [Character] = [
            "C", "D", "E", "F", "G", "H",
            "J", "K", "L", "M", "N", "P",
            "Q", "R", "S", "T", "U", "V",
            "W", "X"
        ]
        if latitude >= 84.0 { return nil }     // UPS north (we declare nil)
        if latitude < -80.0 { return nil }     // UPS south
        // 8° per band; X handles the 12° final band.
        if latitude >= 72.0 { return "X" }
        let idx = Int(floor((latitude + 80.0) / 8.0))
        guard idx >= 0, idx < bands.count - 1 else { return nil }
        return bands[idx]
    }

    // MARK: - Internal: WGS-84 lat/lon → UTM easting/northing

    /// Transverse Mercator projection per WGS-84 reference ellipsoid.
    /// Returns easting/northing in metres for the given central meridian.
    private static func latLonToUTM(
        latitude: Double,
        longitude: Double,
        centralMeridianDeg: Double
    ) -> (easting: Double, northing: Double) {
        // WGS-84 constants.
        let a = 6_378_137.0                                      // equatorial radius
        let f = 1.0 / 298.257223563                              // flattening
        let b = a * (1.0 - f)                                    // polar radius
        let eSq = (a * a - b * b) / (a * a)                      // 1st eccentricity²
        let ePrimeSq = (a * a - b * b) / (b * b)                 // 2nd eccentricity²
        let k0 = 0.9996                                          // UTM scale factor

        let phi = latitude * .pi / 180.0
        let lambda = longitude * .pi / 180.0
        let lambda0 = centralMeridianDeg * .pi / 180.0

        let N = a / sqrt(1.0 - eSq * sin(phi) * sin(phi))
        let T = tan(phi) * tan(phi)
        let C = ePrimeSq * cos(phi) * cos(phi)
        let A = cos(phi) * (lambda - lambda0)

        // Meridional arc — Snyder's coefficient series.
        let M = a * (
            (1.0 - eSq / 4.0 - 3.0 * eSq * eSq / 64.0 - 5.0 * pow(eSq, 3) / 256.0) * phi
            - (3.0 * eSq / 8.0 + 3.0 * eSq * eSq / 32.0 + 45.0 * pow(eSq, 3) / 1024.0) * sin(2.0 * phi)
            + (15.0 * eSq * eSq / 256.0 + 45.0 * pow(eSq, 3) / 1024.0) * sin(4.0 * phi)
            - (35.0 * pow(eSq, 3) / 3072.0) * sin(6.0 * phi)
        )

        // Easting term — Snyder eq. 8-9.
        let easting = k0 * N * (
            A + (1.0 - T + C) * pow(A, 3) / 6.0
            + (5.0 - 18.0 * T + T * T + 72.0 * C - 58.0 * ePrimeSq) * pow(A, 5) / 120.0
        ) + 500_000.0

        // Northing term — Snyder eq. 8-10.
        var northing = k0 * (
            M + N * tan(phi) * (
                A * A / 2.0
                + (5.0 - T + 9.0 * C + 4.0 * C * C) * pow(A, 4) / 24.0
                + (61.0 - 58.0 * T + T * T + 600.0 * C - 330.0 * ePrimeSq) * pow(A, 6) / 720.0
            )
        )
        // Southern hemisphere offset.
        if latitude < 0 {
            northing += 10_000_000.0
        }

        return (easting, northing)
    }

    // MARK: - 100km grid square letters
    //
    // MGRS column letters cycle through three sets of 8 within every
    // group of 6 zones:
    //   set A (zones 1, 4, 7, ...): A-H
    //   set B (zones 2, 5, 8, ...): J-R (skip I and O)
    //   set C (zones 3, 6, 9, ...): S-Z (skip I and O)
    // Wait — actual MGRS column scheme is simpler: each zone has its
    // own 8-letter span based on (zone - 1) % 3:
    //   group 0 (zones 1, 4, 7, ...): A, B, C, D, E, F, G, H
    //   group 1 (zones 2, 5, 8, ...): J, K, L, M, N, P, Q, R
    //   group 2 (zones 3, 6, 9, ...): S, T, U, V, W, X, Y, Z
    //
    // Northing rows use a different 20-letter span:
    //   odd zones (1, 3, ...):  A, B, C, ..., V (skip I, O) — 20 letters
    //   even zones (2, 4, ...): F, G, H, ..., E (skip I, O) — same 20
    //                            letters cycled, offset by 5 rows

    private static let easting1: [Character] = ["A", "B", "C", "D", "E", "F", "G", "H"]
    private static let easting2: [Character] = ["J", "K", "L", "M", "N", "P", "Q", "R"]
    private static let easting3: [Character] = ["S", "T", "U", "V", "W", "X", "Y", "Z"]
    private static let northingOdd: [Character] = [
        "A", "B", "C", "D", "E", "F", "G", "H",
        "J", "K", "L", "M", "N", "P", "Q", "R",
        "S", "T", "U", "V"
    ]
    private static let northingEven: [Character] = [
        "F", "G", "H", "J", "K", "L", "M", "N",
        "P", "Q", "R", "S", "T", "U", "V", "A",
        "B", "C", "D", "E"
    ]

    private static func eastingLetter(zone: Int, idx: Int) -> Character? {
        guard idx >= 0, idx < 8 else { return nil }
        switch (zone - 1) % 3 {
        case 0: return easting1[idx]
        case 1: return easting2[idx]
        case 2: return easting3[idx]
        default: return nil
        }
    }

    private static func northingLetter(zone: Int, idx: Int) -> Character? {
        guard idx >= 0, idx < 20 else { return nil }
        return zone.isMultiple(of: 2) ? northingEven[idx] : northingOdd[idx]
    }
}
