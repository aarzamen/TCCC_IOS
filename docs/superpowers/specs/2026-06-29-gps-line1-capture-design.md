# Design — Production GPS Capture for MEDEVAC Line 1 — 2026-06-29

## Context

MEDEVAC 9-line **Line 1 (LOCATION)** is the loudest datum we transmit. Until
now the operator picked a `LocationSource` in Settings — `.none`, `.manual`
(typed lat/lon), or `.demo` (hardcoded Bagram training coords, `34.5267,
69.1729`). All three are **development affordances**: none reads the device's
real position. This sprint removes them from runtime and replaces them with a
single production source — the iPhone's GPS, encoded to full-precision MGRS by
the existing in-house encoder (`TCCCDomain.MGRS`).

`locationFix` is **transient app state**: it is not in the `EncounterEvent`
log, not in the manifest, not in any export. So widening `LocationFix` needs no
schema migration and touches no event-sourcing invariant. Location never went
through the engine and still doesn't — the engine remains the sole writer of
`PatientState`; this is UI/transient state only.

## RF discipline check (mandatory for any new framework)

CoreLocation is a **passive GNSS receiver**. We open no Wi-Fi/Bluetooth/
cellular/UWB/NFC client, request no continuous tracking, declare no background
location mode, do no reverse geocoding, link no map SDK, and upload nothing.
The OS may use its own Wi-Fi/cell almanac to assist a fix, but that is
OS-internal and carries no casualty data off-device. Casualty/location data
leaves the device only through the existing explicit operator export/share.
**Compliant with RF Ghost.**

## Part A — production-only location model

`AppState.LocationSource` collapses to two cases:

```swift
enum LocationSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case none   // no fix — Line 1 renders UNVERIFIED
    case gps    // real one-shot CoreLocation fix
}
```

`AppState.LocationFix` gains real GPS metadata (new fields default to `nil`,
preserving existing `LocationFix(source: .none, latitude: nil, longitude: nil)`
call sites):

```swift
struct LocationFix: Codable, Sendable, Equatable {
    var source: LocationSource
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracyMeters: Double? = nil
    var verticalAccuracyMeters: Double?   = nil
    var capturedAt: Date?                 = nil
    var authorizationStatusDescription: String?   = nil
    var accuracyAuthorizationDescription: String? = nil
    var isUsable: Bool { source == .gps && latitude != nil && longitude != nil }
}
```

Removed from runtime: the Settings `Location Source` picker, the manual lat/lon
text fields, and the `.demo` Bagram seed. `NineLineEntry.Status.demo` is
deleted (no runtime path produces it). The only remaining Line-1 statuses are
`.ok` (GPS+MGRS valid → ready) and `.pending` (no fix / MGRS failed).

## Part B — Core Location one-shot provider (`TCCC_IOS/App/LocationProvider.swift`)

```swift
protocol LocationProviding: Sendable {
    func requestOneShotFix() async throws -> AppState.LocationFix
}

enum LocationError: Error, Sendable, Equatable { case denied, restricted, unavailable, alreadyInProgress }

@MainActor final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate
```

- `@MainActor`; `CLLocationManager` created on main, delivers callbacks on main;
  delegate methods are `nonisolated` and bounce via `MainActor.assumeIsolated`.
- One `CheckedContinuation` per request; `alreadyInProgress` guards re-entry.
- Flow: read `authorizationStatus`. `.notDetermined` → `requestWhenInUseAuthorization()`,
  then on the authorization callback either `requestLocation()` or resume with
  `.denied`/`.restricted`. `.authorizedWhenInUse/.authorizedAlways` →
  `requestLocation()` immediately. `.denied`/`.restricted` → throw at once.
- `requestLocation()` is **inherently one-shot** — no `startUpdatingLocation`,
  nothing to tear down, no continuous tracking.
- No automatic launch-time request: only `captureGPSFix()` (operator tap) calls it.

The test double (`StubLocationProvider`, returning a canned
`Result<LocationFix, LocationError>`) lives **in the test target only** — never
a runtime mode.

## Part C — permission + AppState capture flow

`project.yml` Info.plist gains (required for the WhenInUse prompt):

```
NSLocationWhenInUseUsageDescription: "Use this iPhone's location to populate
the MEDEVAC Line 1 MGRS grid. Location stays on this device unless the operator
manually exports the casualty record."
```

No new entitlement, no background mode, signing untouched (team `XM6E4PUXTU`,
automatic). The optional `NSLocationTemporaryUsageDescriptionDictionary` is
**not** added: reduced accuracy still yields a usable lat/lon, and MGRS encodes
it fine (only loses digit precision), so temporary-full-accuracy is unnecessary
for Line 1. Revisit only if device testing shows otherwise.

`AppState` gains an injectable provider + a UI status enum:

```swift
enum LocationCaptureStatus: Equatable {
    case noFix, requesting
    case fix(accuracyMeters: Double?)
    case degraded(accuracyMeters: Double?)
    case denied, restricted, mgrsUnavailable
}
@ObservationIgnored var locationProvider: LocationProviding = CoreLocationProvider()
var locationStatus: LocationCaptureStatus = .noFix

func captureGPSFix() async   // requesting → fix/degraded/denied/restricted/mgrsUnavailable
```

`captureGPSFix`: set `.requesting`; await the provider; on success store the
fix and classify — MGRS-nil → `.mgrsUnavailable`, reduced authorization →
`.degraded`, else `.fix`; map `LocationError.denied/.restricted` to their
states and any other failure to `.noFix`. Mutating `locationFix` (observable)
auto-refreshes the MEDEVAC `form`.

## Part E — Line 1 behavior (`NineLineForm`)

Full-precision MGRS only; the decimal-degrees fallback is **deleted**:

- `.none` / not usable → value `"UNVERIFIED — use GPS fix"`, status `.pending`, not ready.
- `.gps` + valid lat/lon + `MGRS.formatted != nil` → the 5+5 MGRS string, status
  `.ok`, `isAuto = true` (badge renders `GPS`), Line 1 ready.
- `.gps` + valid lat/lon + `MGRS.formatted == nil` (polar/UPS) → value
  `"MGRS UNAVAILABLE"`, status `.pending`, not ready.

Expected shape (Bagram fix `34.5267, 69.1729`): `"42S WD 15867 20571"`.
`completedCount` counts Line 1 only when status is `.ok`.

## Part F — UI

MEDEVAC 9-line card gets a `USE GPS FIX` control above the rows (gloved-hand
≥56 pt). Status labels map 1:1 from `LocationCaptureStatus`: `NO FIX`,
`REQUESTING GPS`, `GPS FIX ± Xm`, `GPS DEGRADED ± Xm`, `GPS DENIED` (+ "enable
Location in iOS Settings"), `GPS RESTRICTED`, `MGRS UNAVAILABLE`. `StatusStrip`
provenance badge collapses to `NO FIX` (crit) / `GPS` (accent). No
manual/demo/mock control survives in runtime UI.

## Commit sequence (each compiles + tests green)

1. **Production GPS-only location model** — enum→{none,gps}, widen `LocationFix`,
   rewrite Line 1 (full precision, no fallback), delete `Status.demo`, strip the
   Settings location block + `StatusStrip`/`NineLineRow` cases, rewrite
   `NineLineFormTests`. (Parts A, E, UI-removal)
2. **Core Location provider + permission plist** — `LocationProvider.swift`,
   `project.yml` key, `xcodegen generate`. (Parts B, C-plist)
3. **AppState capture + MEDEVAC USE GPS FIX** — `captureGPSFix`,
   `LocationCaptureStatus`, injected provider, `gpsCaptureBar`; app
   `LocationCaptureTests`. (Parts C-flow, F, G-app)
4. **MGRS precision + nil tests** (kit) — `MGRS.formatted` 5+5 + polar→nil.

## Verification

`swift test` (TCCCKit), app test bundle on a booted sim, `xcodebuild` sim
build. Device smoke test (signed, real iPhone) confirms the permission prompt,
Line 1 population, and the denied/restricted states — that step needs the
physical device and is flagged for the operator.

## Out of scope

Temporary-full-accuracy request; persisting `locationFix` into the event log;
multi-casualty per-patient location; any over-the-air transmission (RF Ghost).
