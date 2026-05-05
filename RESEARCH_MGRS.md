# MGRS Conversion in Swift — Research Notes for TCCC.ai

**Audience:** TCCC.ai (Swift 6, iOS 26, fully on-device, RF Ghost).
**Goal:** WGS-84 lat/lon → MGRS string ("42S WD 12345 67890") for the 9-Line MEDEVAC LINE 1 and Handoff encounter summary. Lat/lon stays the source of truth; MGRS is a derived display string.

---

## 1. Open-source Swift MGRS / UTM packages

### 1a. `ngageoint/mgrs-ios` — primary candidate
- **Repo:** https://github.com/ngageoint/mgrs-ios
- **License:** MIT.
- **Maintenance:** Actively maintained by NGA. Last push 2025-06-06 (v2.0.0). 0–1 open issues.
- **Author:** US National Geospatial-Intelligence Agency + BIT Systems. About as authoritative a source as exists for an MGRS implementation.
- **API surface:** Bidirectional conversion between MGRS / UTM / `GridPoint` (lat/lon). Parsing of MGRS strings, GZD-only strings, and partial-precision strings. Tile/grid line generation for map overlays (irrelevant for us — adds weight).
- **Precision parameter:** First-class. `GridType` enum: `GZD`, `HUNDRED_KILOMETER`, `TEN_KILOMETER`, `KILOMETER`, `HUNDRED_METER`, `TEN_METER`, `METER`. Call `mgrs.coordinate(GridType.METER)` for the 5-digit grid we want.
- **Tests:** Comprehensive. `mgrs-iosTests/MGRSTestCase.swift` covers all precision levels, X-band (the 12°-tall band that includes Svalbard), round-trip parsing, GZD-only, and lat/lon edge cases. The library handles UPS polar zones (A/B/Y/Z designations) per its tile generators.
- **Dependencies:** `ngageoint/grid-ios` (MIT, also NGA, ~6 source files). That's the only transitive dep, and it's pure Swift / Foundation. No networking, no Bluetooth, no analytics. **Compatible with RF Ghost.**
- **Platforms:** iOS 13+, macOS 11+, Swift 5.10. Works fine on our iOS 17+ target.
- **Footprint:** `mgrs-ios` source ≈ 26 KB main file + supporting files. `grid-ios` ≈ 35 KB. Bundled together that's a small, focused dependency — not a hidden monster.

### 1b. `wtw-software/ios-UTMConversion` — UTM only, no MGRS
- **Repo:** https://github.com/wtw-software/ios-UTMConversion
- **License:** MIT. Maintained (last push 2026-04). 27 stars.
- **Scope:** Lat/lon ↔ UTM only. Does **not** emit MGRS strings. Would require us to implement the UTM → MGRS step (100km grid letters, truncation) ourselves.
- **Verdict:** Useful only if we wanted UTM as an intermediate. Skip in favor of mgrs-ios.

### 1c. `blacksmithdevelopers/MGRSConverter` — abandoned
- **Repo:** https://github.com/blacksmithdevelopers/MGRSConverter
- **License:** MIT. **Last commit 2020-05-07.** 12 stars, 8 total commits, no documented test suite, no accuracy claims.
- **Verdict:** Hobby-grade, stale. Don't use.

### 1d. ArcGIS Runtime SDK — non-starter
- Esri's `AGSMGRSGrid` is a closed-source SDK with a license that requires a paid Esri Developer subscription for production use. Also pulls in a heavy framework. Skip.

---

## 2. Reference implementations in other languages

- **Apple MapKit / Core Location:** **No native MGRS support.** `CLLocationCoordinate2D` is lat/lon only; `MKMapView` has no MGRS overlay. Confirmed via Apple Developer Forums and current MapKit docs.
- **GeographicLib (C++) by Charles Karney:** The reference. `GeographicLib::MGRS` documents accuracy as exact for precision 0–5 except within 5 nautical miles of latitude band boundaries (handled by allowing neighbor letters). https://geographiclib.sourceforge.io/C++/doc/classGeographicLib_1_1MGRS.html
- **`hobuinc/mgrs` (Python):** ctypes wrapper around NGA's GeoTrans C code. The de facto Python reference. https://github.com/hobuinc/mgrs
- **`PyGeodesy` (Python):** Pure-Python transcoding of Karney's C++ MGRS class. Useful as a readable algorithmic reference.
- **`ngageoint/mgrs-java`:** Sister project to `mgrs-ios`. Same algorithm. Useful for cross-checking output.

We used `hobuinc/mgrs` in a venv (`uv venv --python 3.12 && uv pip install mgrs packaging`) to generate the canonical fixtures in §5 below.

---

## 3. Algorithm essentials (if we ever implement from scratch)

### WGS-84 ellipsoid constants
```
a (semi-major axis) = 6_378_137.0 m
f (flattening)      = 1 / 298.257_223_563
e²                  = 2f - f²        ≈ 0.006_694_379_990_14
e'²                 = e² / (1 - e²)
k0 (UTM scale)      = 0.9996
```

### UTM zone derivation
```
zoneNumber = floor((longitude + 180) / 6) + 1            // 1..60
bandLetter = "CDEFGHJKLMNPQRSTUVWX"[ floor((latitude + 80) / 8) ]
            // bands C..X, 8° each; band X is 12° tall (72°N..84°N)
            // 'I' and 'O' are excluded for legibility
```

### Norway / Svalbard exceptions (mandatory if we hand-roll)
- **31V → 32V:** if `56°N ≤ lat < 64°N` and `3°E ≤ lon < 12°E` then zone = 32 (this is the case Bergen, 60°N 5°E, exercises).
- **Svalbard (band X, 72°N..84°N):**
  - `0°E ≤ lon < 9°E` → zone 31
  - `9°E ≤ lon < 21°E` → zone 33
  - `21°E ≤ lon < 33°E` → zone 35
  - `33°E ≤ lon < 42°E` → zone 37
  (Zones 32, 34, 36 are skipped in band X.)

### MGRS 100km grid letters (AA scheme — the WGS-84 scheme)
- **Column letter** (easting): cycles through `ABCDEFGH` / `JKLMNPQR` / `STUVWXYZ` based on `zoneNumber mod 3`. `I` and `O` are skipped. The set repeats every three zones.
- **Row letter** (northing): runs `A..V` (skipping `I` and `O`), repeating every 2,000 km. Odd-numbered zones start at `A` at the equator; even-numbered zones offset by 5 letters and start at `F`.

### Easting / northing → 5-digit grid
After computing UTM `(E, N)` in metres:
```
column100km = floor(E / 100_000)        // pick the column letter for this zone & index
row100km    = floor(N / 100_000) % 20   // mod 20 because rows repeat every 2000 km
gridEasting  = floor(E % 100_000)       // 0..99_999
gridNorthing = floor(N % 100_000)       // 0..99_999
```
Format with 5 zero-padded digits each. **MGRS truncates, never rounds** (per movable-type.co.uk and Karney's docs) — this matters for parity with reference implementations.

### UPS polar regions (out of scope for TCCC.ai)
Above 84°N or below 80°S, MGRS uses Universal Polar Stereographic with grid zones `A`, `B`, `Y`, `Z` instead of UTM zones. Different math (polar stereographic projection, not transverse Mercator).

---

## 4. Recommended path: ship UTM-only? Or full library?

**TCCC.ai battlefield use case never lands above 84°N or below 80°S.** A casualty in McMurdo Station is a science-mission medical event, not a TCCC scenario. So skipping UPS is defensible.

However: the *implementation cost difference* between "UTM-only with Norway exceptions" and "full mgrs-ios via SPM" is heavily in the library's favor:

| Path | Lines of Swift to own | Edge cases we own | Test burden |
|---|---|---|---|
| Hand-rolled UTM-only | ~200–300 | Norway 31→32, Svalbard 31/33/35/37, AA scheme letter assignment, truncation, X-band 12° | Need to mirror `hobuinc/mgrs` outputs for ~30+ fixtures |
| `mgrs-ios` via SPM | 0 (just call site) | All handled upstream | 4 sanity-check tests |

The library is small, MIT, has the NGA's name on it, and pulls in only one transitive dep that is also NGA-maintained Swift. **Adopt the library.**

The "implement from scratch" exit hatch is documented in §3 above so we can pivot if the library ever drifts.

---

## 5. Test fixtures (canonical, generated via `hobuinc/mgrs` → GeoTrans)

| Description | Lat | Lon | MGRS @ 5-digit | MGRS @ 10-km | GZD |
|---|---|---|---|---|---|
| Bagram-ish (default GPS) | 34.5267 N | 69.1729 E | `42SWD1586720571` | `42SWD1520` | `42S` |
| Origin | 0 | 0 | `31NAA6602100000` | `31NAA6600` | `31N` |
| Washington DC | 38.8977 N | 77.0365 W | `18SUJ2339407395` | `18SUJ2307` | `18S` |
| Bergen, Norway (zone exception) | 60 N | 5 E | `32VKM7697958157` | `32VKM7658` | `32V` |

**Bergen sanity check:** at 5°E it would normally fall in zone 31, but the Norway exception puts it in **32V**. That's the canonical test for whether the implementation handles the Norway shift. `hobuinc/mgrs` confirms 32V.

**Display formatting:** we'll likely want spaces in the rendered string ("42S WD 15867 20571") for legibility. `mgrs-ios` returns concatenated. A trivial Swift extension over `String` inserts the spaces — recommend keeping the engine output unspaced and formatting at the view layer.

Additional fixtures generated for cross-checking (use as needed):
- Khulani Sq, Baghdad (33.32 N, 44.42 E) → `38SMB4601486913` (matches GeographicLib's published example to 1 km: `38SMB4488`)
- San Francisco (37.7749 N, 122.4194 W) → `10SEG5113080998`
- Sydney (33.8688 S, 151.2093 E) → `56HLH3436850948`
- Anchorage (61.2181 N, 149.9003 W) → `06VUN4424790536`

---

## 6. Recommendation

**Use `ngageoint/mgrs-ios` via Swift Package Manager.**

### Install (add to `Packages/TCCCKit/Package.swift`)
```swift
dependencies: [
    .package(url: "https://github.com/ngageoint/mgrs-ios.git", from: "2.0.0"),
],
targets: [
    .target(
        name: "TCCCDomain",
        dependencies: [
            .product(name: "MGRS", package: "mgrs-ios"),
        ]
    ),
    // ...
],
```

### Sample call site
```swift
import MGRS

public enum MGRSFormatter {
    /// 5-digit (1m) grid string. Returns nil if the input is non-finite.
    public static func string(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        let point = GridPoint(longitude, latitude)         // note: lon, lat order
        let mgrs = MGRS.from(point)
        return mgrs.coordinate(GridType.METER)             // e.g. "42SWD1586720571"
    }

    /// Display variant with spaces: "42S WD 15867 20571".
    public static func displayString(latitude: Double, longitude: Double) -> String? {
        guard let raw = string(latitude: latitude, longitude: longitude),
              raw.count >= 15 else { return nil }
        let gzd  = String(raw.prefix(3))                   // "42S"
        let sq   = String(raw.dropFirst(3).prefix(2))      // "WD"
        let east = String(raw.dropFirst(5).prefix(5))      // "15867"
        let nort = String(raw.suffix(5))                   // "20571"
        return "\(gzd) \(sq) \(east) \(nort)"
    }
}
```

### Pitfalls / gotchas
1. **`GridPoint(longitude, latitude)` is `lon, lat` order** — easy to get wrong. Add a unit test that covers Bagram/DC to catch a swap.
2. The library's `mgrs.description` returns concatenated string with no spaces. Format at the view layer.
3. The `mgrs.plist` resource ships inside the `MGRS` SPM product and is loaded at runtime. SPM handles this; just don't strip it from the bundle in any custom build script.
4. iOS 13+ deployment target — fine for us (iOS 17+).
5. Heads-up for tile/overlay code: `mgrs-ios` includes grid-tile rendering (`Grid`, `GridZones`, etc.) we don't need. The linker should dead-strip it; if the binary feels heavy, audit with `--print-link-map`.

### If we ever need to vendor instead of importing
The library is MIT, so we can copy `MGRS.swift` + `MGRSConstants.swift` + `MGRSUtils.swift` + the relevant `grid-ios` files into `Packages/TCCCKit/Sources/TCCCDomain/MGRS/` and drop the dependency. Worth doing only if SPM resolution becomes a problem at build time. Today, just import.

---

## Sources

- [ngageoint/mgrs-ios](https://github.com/ngageoint/mgrs-ios) — primary recommendation
- [ngageoint/grid-ios](https://github.com/ngageoint/grid-ios) — transitive dep
- [mgrs-ios MGRSTestCase.swift](https://github.com/ngageoint/mgrs-ios/blob/master/mgrs-iosTests/MGRSTestCase.swift) — test scope reference
- [wtw-software/ios-UTMConversion](https://github.com/wtw-software/ios-UTMConversion) — UTM-only alternative
- [blacksmithdevelopers/MGRSConverter](https://github.com/blacksmithdevelopers/MGRSConverter) — abandoned
- [Wikipedia: Military Grid Reference System](https://en.wikipedia.org/wiki/Military_Grid_Reference_System) — algorithm reference, AA scheme, Norway/Svalbard exceptions
- [movable-type.co.uk lat/lon ↔ UTM/MGRS](https://www.movable-type.co.uk/scripts/latlong-utm-mgrs.html) — Karney method, truncation note
- [GeographicLib MGRS class](https://geographiclib.sourceforge.io/C++/doc/classGeographicLib_1_1MGRS.html) — accuracy claims, edge cases
- [hobuinc/mgrs (Python)](https://github.com/hobuinc/mgrs) — used to generate canonical fixtures in §5
- [maptools.com 100km square ID](https://maptools.com/tutorials/100km_square_id) — column/row letter scheme
- [USNG Florida: Trapped in Afghanistan](https://medium.com/@USNGFlorida/trapped-in-afghanistan-d2d9306f0771) — Bagram/Kabul are 42S WD (sanity check)
