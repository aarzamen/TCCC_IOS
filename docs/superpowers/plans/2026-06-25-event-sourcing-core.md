# Event-Sourcing Core (Sub-cycle A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `PatientState` a deterministic projection (fold) of an immutable, fat `EncounterEvent` log — in memory — without changing any observable engine behavior (726 TCCCKit + 67 app tests stay green).

**Architecture:** CQRS-shaped. The command path (`processTranscript`, operator accept/reject) runs the existing logic once and emits events into an append-only `EncounterLog`. The projection (`project(log)`) folds the log by **replaying recorded deltas** — it never re-runs extractors, so it is deterministic (captured `Intervention` UUIDs/timestamps are replayed verbatim). The flip from imperative state to `patients = project(log)` is gated by an equivalence test proving `project(log) == imperative result` field-by-field over the four real scenario fixtures.

**Tech Stack:** Swift 6 strict concurrency, `actor PatientStateEngine` (TCCCKit/`TCCCExtractor`), value-typed `Codable`/`Sendable` domain model, XCTest. Foundation only — no new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-25-event-sourcing-core-design.md`.

## Global Constraints

- **726 TCCCKit + 67 app tests stay green at every task boundary** — not just at the end.
- **The engine is the SOLE writer of `PatientState`.** After the flip, state flows only from `project(log)`; the only mutation primitives are `applyWrite` (operator vocabulary) and `applyDelta` (extractor-diff vocabulary), both engine-internal.
- **LLM-never-mutates-state stays structural.** Operator-origin facts reach state only via `OperatorAcceptedFact` → `FieldRouter` → `PatientStateFieldWrite`, now wrapped in an `operatorAcceptedFact` event. No new mutation entry point.
- **Module placement:** all new types live in **TCCCKit / `TCCCExtractor`** (the module that already holds `PatientStateEngine` and `PatientStateFieldWrite`). This avoids relocating `PatientStateFieldWrite` across modules and keeps the fold logic cohesive. (The spec said "TCCCKit"; `TCCCExtractor` is the chosen submodule — no app-target dependency is introduced.)
- **`project` is a pure `nonisolated static` function** so it is testable without the actor and cannot accidentally read actor state.
- **`diff` must be total:** `apply(diff(before, after)) == after` for any pair the extractors can produce.
- **In-memory only.** No persistence, no disk, no archive, no lifecycle PRESERVE/PURGE — those are sub-cycle B. Do not add file I/O.
- **No `Date.now`/`UUID()` introduced into the projection path.** Determinism comes from replaying captured values.

**Build / verify commands**
- TCCCKit (Tasks A1–A3, A5 verification, A8): `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`
  - Single suite: append `--filter <SuiteName>`.
- App target (Tasks A4, A6, A7): regenerate + build/test on the working destination:
  ```bash
  cd /Users/ama/TCCC_IOS && xcodegen generate && \
  xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
    -destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation \
    -only-testing:TCCC_IOSTests/<Suite>/<method>
  ```
  - `generic/platform=iOS Simulator` and bare `id=` FAIL — use the exact `platform=iOS Simulator,id=…` form.
  - Class-level `-only-testing:Target/Class` reports 0 tests on this sim — use `Target/Class/method` or a full-suite run.
  - **Any task that adds a NEW file under `TCCC_IOS/` must `git add TCCC_IOS.xcodeproj/project.pbxproj`** (xcodegen regenerates it). TCCCKit/SPM tasks do not touch the pbxproj.

---

## File Structure

**New (TCCCKit / `TCCCExtractor`):**
- `Sources/TCCCExtractor/EncounterEvent.swift` — `PatientStateDelta`, `EncounterEvent` + 4 payload structs, `EncounterLog`.
- `Sources/TCCCExtractor/PatientStateProjection.swift` — `applyWrite`, `applyDelta`, `diff`, `project` (all on `extension PatientStateEngine`, pure/`nonisolated static`).
- `Tests/TCCCExtractorTests/EncounterEventTests.swift` — A1.
- `Tests/TCCCExtractorTests/PatientStateDiffTests.swift` — A2 (inverse property, every delta case).
- `Tests/TCCCExtractorTests/LogEquivalenceTests.swift` — A3 (the de-risker) + A5 re-verify.
- `Tests/TCCCExtractorTests/EngineInvariantTests.swift` — A7/A8 enum-sync + invariant.

**Modified (TCCCKit / `TCCCExtractor`):**
- `Sources/TCCCExtractor/PatientStateEngine.swift` — gains `log`, event emission in `processTranscript` (A3) + the flip (A5); `apply` refactored to use `applyWrite` (A2) and `recordOperatorAcceptedFact`/`recordOperatorRejectedFact` (A4) + their flip (A5); `encounterStarted` lifecycle event (A8).

**Modified (app):**
- `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` — `acceptGraniteFact`/`rejectGraniteReviewItem` route to the engine's event-recording methods (A4); evidence surfaced from events (A6).
- `TCCC_IOS/Intelligence/DeterministicFactProjector.swift` — evidence from events; remove `evidenceIds: []` stopgap (A6).
- `TCCC_IOSTests/...` — A4/A6/A7 app-side tests.

---

## Task A1: EncounterEvent value types

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCExtractor/EncounterEvent.swift`
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/EncounterEventTests.swift`

**Interfaces:**
- Produces: `PatientStateDelta` (36-case enum — one per writable field of PatientState/MARCHState/Vitals/PAWS; `patientId` is the identity key, not a delta), `EncounterEvent` (5 cases) + `ASRSegmentPayload`, `DeterministicFactPayload`, `OperatorDecisionPayload`, `LifecyclePayload`, `EncounterLog`. Consumed by every later task.
- Consumes: `PatientState`, `MARCHState`, `Vitals`, `BloodPressure`, `Intervention`, `MarchPhase`, `Classification` (TCCCDomain); `PatientStateFieldWrite` (TCCCExtractor).

- [ ] **Step 1: Write the failing test**

```swift
// Packages/TCCCKit/Tests/TCCCExtractorTests/EncounterEventTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class EncounterEventTests: XCTestCase {

    private func roundTrip(_ event: EncounterEvent) throws -> EncounterEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(EncounterEvent.self, from: data)
    }

    func testASRSegmentRoundTripsAndExposesIdentity() throws {
        let event = EncounterEvent.asrSegment(.init(
            id: "seg-1", patientId: "PATIENT_1", timestampUnix: 1000,
            text: "GSW right thigh", backend: "appleSpeech", isFinal: true))
        XCTAssertEqual(try roundTrip(event), event)
        XCTAssertEqual(event.id, "seg-1")
        XCTAssertEqual(event.patientId, "PATIENT_1")
        XCTAssertEqual(event.timestampUnix, 1000)
    }

    func testDeterministicFactCarriesDeltaAndEvidence() throws {
        let event = EncounterEvent.deterministicFact(.init(
            id: "fact-1", patientId: "PATIENT_1", timestampUnix: 1000,
            delta: .vitalsHR(110), evidenceIds: ["seg-1"], extractor: "VitalsExtractor"))
        XCTAssertEqual(try roundTrip(event), event)
        if case .deterministicFact(let p) = event { XCTAssertEqual(p.delta, .vitalsHR(110)) }
        else { XCTFail("wrong case") }
    }

    func testOperatorAcceptedAndRejectedRoundTrip() throws {
        let accepted = EncounterEvent.operatorAcceptedFact(.init(
            id: "op-1", patientId: "PATIENT_1", timestampUnix: 1000,
            write: .heartRate(110), sourceFactId: "g-1",
            domain: "vitals", field: "heartRate", rawValue: "110"))
        let rejected = EncounterEvent.operatorRejectedFact(.init(
            id: "op-2", patientId: "PATIENT_1", timestampUnix: 1001,
            write: nil, sourceFactId: "g-2",
            domain: "vitals", field: "heartRate", rawValue: "200"))
        XCTAssertEqual(try roundTrip(accepted), accepted)
        XCTAssertEqual(try roundTrip(rejected), rejected)
    }

    func testLifecycleRoundTrips() throws {
        let event = EncounterEvent.lifecycle(.init(
            id: "lc-1", patientId: "PATIENT_1", timestampUnix: 1000, kind: .encounterStarted))
        XCTAssertEqual(try roundTrip(event), event)
    }

    func testEncounterLogAppendsAndIsImmutableFromOutside() throws {
        var log = EncounterLog()
        XCTAssertTrue(log.events.isEmpty)
        log.append(.lifecycle(.init(id: "lc-1", patientId: "PATIENT_1", timestampUnix: 1, kind: .encounterStarted)))
        log.append(.asrSegment(.init(id: "seg-1", patientId: "PATIENT_1", timestampUnix: 2, text: "x", backend: "demo", isFinal: true)))
        XCTAssertEqual(log.events.count, 2)
        XCTAssertEqual(log.events.first?.id, "lc-1")
        // events has no public setter — this line must not compile if uncommented:
        // log.events = []
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(EncounterLog.self, from: data), log)
    }

    func testDeltaCodableRoundTripForRepresentativeCases() throws {
        let deltas: [PatientStateDelta] = [
            .mechanismOfInjury("GSW"), .marchPhase(.massive), .classification(.urgent),
            .appendInjury("femur fracture"), .setInjuries(["a", "b"]),
            .vitalsBP(BloodPressure(systolic: 90, diastolic: 60, palpated: false)),
            .hemorrhageIntervention("tourniquet applied"), .pawsPain("ketamine"),
            .appendIntervention(Intervention(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                timestamp: Date(timeIntervalSince1970: 5), kind: .tourniquet, description: "TQ")),
        ]
        for d in deltas {
            let data = try JSONEncoder().encode(d)
            XCTAssertEqual(try JSONDecoder().decode(PatientStateDelta.self, from: data), d)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter EncounterEventTests`
Expected: FAIL — `cannot find 'EncounterEvent' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Packages/TCCCKit/Sources/TCCCExtractor/EncounterEvent.swift
import Foundation
import TCCCDomain

/// A typed, audit-grain representation of a single mutation to `PatientState`.
/// Spans every writable field of `PatientState` and its nested structs so that
/// `apply(diff(before, after)) == after` holds for any extractor output.
public enum PatientStateDelta: Sendable, Codable, Equatable {
    // PatientState scalars
    case mechanismOfInjury(String?)
    case marchPhase(MarchPhase)
    case classification(Classification?)
    case timestampFirstMention(Double?)
    case timestampLastUpdate(Double?)
    // PatientState collections
    case appendInjury(String)
    case setInjuries([String])
    case appendIntervention(Intervention)
    case setInterventions([Intervention])
    // Vitals
    case vitalsHR(Int?)
    case vitalsBP(BloodPressure?)
    case vitalsSpO2(Int?)
    case vitalsRR(Int?)
    case vitalsGCS(Int?)
    case vitalsTemperatureCelsius(Double?)
    case vitalsCapillaryRefillSeconds(Double?)
    // MARCHState
    case hemorrhageIdentified(Bool)
    case hemorrhageAssessed(Bool)
    case hemorrhageLocation(String?)
    case hemorrhageIntervention(String?)
    case hemorrhageEffective(Bool?)
    case airwayStatus(String?)
    case airwayIntervention(String?)
    case respirationStatus(String?)
    case respirationIntervention(String?)
    case breathSounds(String?)
    case pulseStatus(String?)
    case skinSigns(String?)
    case circulationIntervention(String?)
    case consciousness(String?)
    case pupilResponse(String?)
    case hypothermiaPrevention(String?)
    // PAWS
    case pawsPain(String?)
    case pawsAntibiotics(String?)
    case pawsWounds(String?)
    case pawsSplinting(String?)
}

public struct ASRSegmentPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let text: String
    public let backend: String
    public let isFinal: Bool
    public init(id: String, patientId: String, timestampUnix: Double, text: String, backend: String, isFinal: Bool) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.text = text; self.backend = backend; self.isFinal = isFinal
    }
}

public struct DeterministicFactPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let delta: PatientStateDelta
    public let evidenceIds: [String]
    public let extractor: String
    public init(id: String, patientId: String, timestampUnix: Double, delta: PatientStateDelta, evidenceIds: [String], extractor: String) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.delta = delta; self.evidenceIds = evidenceIds; self.extractor = extractor
    }
}

public struct OperatorDecisionPayload: Sendable, Codable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let write: PatientStateFieldWrite?   // accepted+routable: applied write; rejected/unroutable: nil
    public let sourceFactId: String?
    public let domain: String
    public let field: String
    public let rawValue: String?
    public init(id: String, patientId: String, timestampUnix: Double, write: PatientStateFieldWrite?, sourceFactId: String?, domain: String, field: String, rawValue: String?) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix
        self.write = write; self.sourceFactId = sourceFactId
        self.domain = domain; self.field = field; self.rawValue = rawValue
    }
}

public struct LifecyclePayload: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable { case encounterStarted, encounterEnded, archived }
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let kind: Kind
    public init(id: String, patientId: String, timestampUnix: Double, kind: Kind) {
        self.id = id; self.patientId = patientId; self.timestampUnix = timestampUnix; self.kind = kind
    }
}

/// One immutable record in the encounter log.
public enum EncounterEvent: Sendable, Codable, Equatable, Identifiable {
    case asrSegment(ASRSegmentPayload)
    case deterministicFact(DeterministicFactPayload)
    case operatorAcceptedFact(OperatorDecisionPayload)
    case operatorRejectedFact(OperatorDecisionPayload)
    case lifecycle(LifecyclePayload)

    public var id: String {
        switch self {
        case .asrSegment(let p): return p.id
        case .deterministicFact(let p): return p.id
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.id
        case .lifecycle(let p): return p.id
        }
    }
    public var patientId: String {
        switch self {
        case .asrSegment(let p): return p.patientId
        case .deterministicFact(let p): return p.patientId
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.patientId
        case .lifecycle(let p): return p.patientId
        }
    }
    public var timestampUnix: Double {
        switch self {
        case .asrSegment(let p): return p.timestampUnix
        case .deterministicFact(let p): return p.timestampUnix
        case .operatorAcceptedFact(let p), .operatorRejectedFact(let p): return p.timestampUnix
        case .lifecycle(let p): return p.timestampUnix
        }
    }
}

/// Append-only canonical record of one casualty's encounter.
public struct EncounterLog: Sendable, Codable, Equatable {
    public private(set) var events: [EncounterEvent]
    public init(events: [EncounterEvent] = []) { self.events = events }
    public mutating func append(_ event: EncounterEvent) { events.append(event) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter EncounterEventTests`
Expected: PASS (6 tests). Then full suite: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → 732 passing (726 + 6).

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/EncounterEvent.swift Packages/TCCCKit/Tests/TCCCExtractorTests/EncounterEventTests.swift
git commit -m "feat(event-sourcing): EncounterEvent + PatientStateDelta + EncounterLog value types"
```

---

## Task A2: diff + apply primitives (the inverse property)

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift`
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift:130-152` (route `apply` through `applyWrite`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateDiffTests.swift`

**Interfaces:**
- Produces: `static func applyWrite(_:to:)`, `static func applyDelta(_:to:)`, `static func diff(_:_:) -> [PatientStateDelta]` on `extension PatientStateEngine`. Consumed by A3 `project` and A4/A5.
- Consumes: A1 types.

- [ ] **Step 1: Write the failing test**

```swift
// Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateDiffTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PatientStateDiffTests: XCTestCase {

    /// The central correctness obligation: replaying the diff reconstructs `after`.
    private func assertInverse(_ before: PatientState, _ after: PatientState,
                               file: StaticString = #filePath, line: UInt = #line) {
        let deltas = PatientStateEngine.diff(before, after)
        var rebuilt = before
        for d in deltas { PatientStateEngine.applyDelta(d, to: &rebuilt) }
        XCTAssertEqual(rebuilt, after, "diff+apply did not reconstruct after", file: file, line: line)
    }

    func testInverseHoldsForEveryScalarFieldFamily() {
        let base = PatientState(patientId: "PATIENT_1")
        var a = base; a.mechanismOfInjury = "GSW"; assertInverse(base, a)
        var b = base; b.marchPhase = .circulation; assertInverse(base, b)
        var c = base; c.classification = .urgentSurgical; assertInverse(base, c)
        var d = base; d.timestampFirstMention = 12; d.timestampLastUpdate = 34; assertInverse(base, d)
        var e = base; e.vitals.hr = 110; e.vitals.spo2 = 96; e.vitals.rr = 18
        e.vitals.gcs = 14; e.vitals.temperatureCelsius = 36.5; e.vitals.capillaryRefillSeconds = 2.0
        e.vitals.bp = BloodPressure(systolic: 90, diastolic: 60, palpated: true); assertInverse(base, e)
        var f = base
        f.march.hemorrhageIdentified = true; f.march.hemorrhageAssessed = true
        f.march.hemorrhageLocation = "right thigh"; f.march.hemorrhageIntervention = "tourniquet"
        f.march.hemorrhageEffective = true; f.march.airwayStatus = "patent"
        f.march.airwayIntervention = "NPA"; f.march.respirationStatus = "labored"
        f.march.respirationIntervention = "chest seal"; f.march.breathSounds = "bilateral equal"
        f.march.pulseStatus = "weak radial"; f.march.skinSigns = "cool clammy"
        f.march.circulationIntervention = "IV access"; f.march.consciousness = "Alert"
        f.march.pupilResponse = "PERRL"; f.march.hypothermiaPrevention = "wrap"; assertInverse(base, f)
        var g = base; g.paws.pain = "ketamine"; g.paws.antibiotics = "moxifloxacin"
        g.paws.wounds = "wound care"; g.paws.splinting = "SAM splint"; assertInverse(base, g)
    }

    func testInverseHoldsForCollectionAppend() {
        let base = PatientState(patientId: "PATIENT_1")
        var a = base
        a.injuries = ["femur fracture", "laceration"]
        a.interventions = [
            Intervention(timestamp: Date(timeIntervalSince1970: 1), kind: .tourniquet, description: "TQ"),
            Intervention(timestamp: Date(timeIntervalSince1970: 2), kind: .npa, description: "NPA"),
        ]
        // append-only growth → expect append deltas, and inverse holds (UUIDs preserved)
        let deltas = PatientStateEngine.diff(base, a)
        XCTAssertTrue(deltas.contains { if case .appendInjury = $0 { return true }; return false })
        XCTAssertTrue(deltas.contains { if case .appendIntervention = $0 { return true }; return false })
        assertInverse(base, a)
    }

    func testInverseHoldsForNonPrefixCollectionChangeViaSetFallback() {
        var before = PatientState(patientId: "PATIENT_1")
        before.injuries = ["x", "y"]
        var after = before
        after.injuries = ["z"]               // not a prefix-extension of before → set fallback
        let deltas = PatientStateEngine.diff(before, after)
        XCTAssertTrue(deltas.contains { if case .setInjuries = $0 { return true }; return false })
        assertInverse(before, after)
    }

    func testInverseHoldsClearingOptionalToNil() {
        var before = PatientState(patientId: "PATIENT_1")
        before.mechanismOfInjury = "GSW"; before.vitals.hr = 110
        var after = before
        after.mechanismOfInjury = nil; after.vitals.hr = nil
        assertInverse(before, after)
    }

    func testEmptyDiffWhenUnchanged() {
        let s = PatientState(patientId: "PATIENT_1")
        XCTAssertTrue(PatientStateEngine.diff(s, s).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter PatientStateDiffTests`
Expected: FAIL — `type 'PatientStateEngine' has no member 'diff'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift
import Foundation
import TCCCDomain

extension PatientStateEngine {

    /// Apply one operator-vocabulary write. Pure field-set (no timestamp side effect);
    /// the engine and the projection own timestamp semantics around it.
    nonisolated static func applyWrite(_ write: PatientStateFieldWrite, to p: inout PatientState) {
        switch write {
        case .heartRate(let v):              p.vitals.hr = v
        case .spo2(let v):                   p.vitals.spo2 = v
        case .respiratoryRate(let v):        p.vitals.rr = v
        case .bloodPressure(let s, let d, let pal):
            p.vitals.bp = BloodPressure(systolic: s, diastolic: d, palpated: pal)
        case .hemorrhageLocation(let v):     p.march.hemorrhageLocation = v
        case .hemorrhageIntervention(let v): p.march.hemorrhageIntervention = v
        case .airwayIntervention(let v):     p.march.airwayIntervention = v
        case .consciousness(let v):          p.march.consciousness = v
        case .hypothermiaPrevention(let v):  p.march.hypothermiaPrevention = v
        case .pain(let v):                   p.paws.pain = v
        case .antibiotics(let v):            p.paws.antibiotics = v
        }
    }

    /// Apply one audit-grain delta. Direct field assignment is intentional — the
    /// value was produced by a validated extractor pass; re-validation would change it
    /// and break the inverse property.
    nonisolated static func applyDelta(_ delta: PatientStateDelta, to p: inout PatientState) {
        switch delta {
        case .mechanismOfInjury(let v):          p.mechanismOfInjury = v
        case .marchPhase(let v):                 p.marchPhase = v
        case .classification(let v):             p.classification = v
        case .timestampFirstMention(let v):      p.timestampFirstMention = v
        case .timestampLastUpdate(let v):        p.timestampLastUpdate = v
        case .appendInjury(let v):               p.injuries.append(v)
        case .setInjuries(let v):                p.injuries = v
        case .appendIntervention(let v):         p.interventions.append(v)
        case .setInterventions(let v):           p.interventions = v
        case .vitalsHR(let v):                   p.vitals.hr = v
        case .vitalsBP(let v):                   p.vitals.bp = v
        case .vitalsSpO2(let v):                 p.vitals.spo2 = v
        case .vitalsRR(let v):                   p.vitals.rr = v
        case .vitalsGCS(let v):                  p.vitals.gcs = v
        case .vitalsTemperatureCelsius(let v):   p.vitals.temperatureCelsius = v
        case .vitalsCapillaryRefillSeconds(let v): p.vitals.capillaryRefillSeconds = v
        case .hemorrhageIdentified(let v):       p.march.hemorrhageIdentified = v
        case .hemorrhageAssessed(let v):         p.march.hemorrhageAssessed = v
        case .hemorrhageLocation(let v):         p.march.hemorrhageLocation = v
        case .hemorrhageIntervention(let v):     p.march.hemorrhageIntervention = v
        case .hemorrhageEffective(let v):        p.march.hemorrhageEffective = v
        case .airwayStatus(let v):               p.march.airwayStatus = v
        case .airwayIntervention(let v):         p.march.airwayIntervention = v
        case .respirationStatus(let v):          p.march.respirationStatus = v
        case .respirationIntervention(let v):    p.march.respirationIntervention = v
        case .breathSounds(let v):               p.march.breathSounds = v
        case .pulseStatus(let v):                p.march.pulseStatus = v
        case .skinSigns(let v):                  p.march.skinSigns = v
        case .circulationIntervention(let v):    p.march.circulationIntervention = v
        case .consciousness(let v):              p.march.consciousness = v
        case .pupilResponse(let v):              p.march.pupilResponse = v
        case .hypothermiaPrevention(let v):      p.march.hypothermiaPrevention = v
        case .pawsPain(let v):                   p.paws.pain = v
        case .pawsAntibiotics(let v):            p.paws.antibiotics = v
        case .pawsWounds(let v):                 p.paws.wounds = v
        case .pawsSplinting(let v):              p.paws.splinting = v
        }
    }

    /// Total diff: `apply(diff(before, after)) == after`. Scalars/optionals emit a
    /// set-delta on change; collections emit per-element append deltas when `after`
    /// extends `before` as a prefix, else a whole-array set fallback.
    nonisolated static func diff(_ before: PatientState, _ after: PatientState) -> [PatientStateDelta] {
        var d: [PatientStateDelta] = []
        // PatientState scalars
        if before.mechanismOfInjury != after.mechanismOfInjury { d.append(.mechanismOfInjury(after.mechanismOfInjury)) }
        if before.marchPhase != after.marchPhase { d.append(.marchPhase(after.marchPhase)) }
        if before.classification != after.classification { d.append(.classification(after.classification)) }
        if before.timestampFirstMention != after.timestampFirstMention { d.append(.timestampFirstMention(after.timestampFirstMention)) }
        if before.timestampLastUpdate != after.timestampLastUpdate { d.append(.timestampLastUpdate(after.timestampLastUpdate)) }
        // Collections
        appendCollectionDiff(before.injuries, after.injuries, into: &d,
                             append: { .appendInjury($0) }, set: { .setInjuries($0) })
        appendCollectionDiff(before.interventions, after.interventions, into: &d,
                             append: { .appendIntervention($0) }, set: { .setInterventions($0) })
        // Vitals
        if before.vitals.hr != after.vitals.hr { d.append(.vitalsHR(after.vitals.hr)) }
        if before.vitals.bp != after.vitals.bp { d.append(.vitalsBP(after.vitals.bp)) }
        if before.vitals.spo2 != after.vitals.spo2 { d.append(.vitalsSpO2(after.vitals.spo2)) }
        if before.vitals.rr != after.vitals.rr { d.append(.vitalsRR(after.vitals.rr)) }
        if before.vitals.gcs != after.vitals.gcs { d.append(.vitalsGCS(after.vitals.gcs)) }
        if before.vitals.temperatureCelsius != after.vitals.temperatureCelsius { d.append(.vitalsTemperatureCelsius(after.vitals.temperatureCelsius)) }
        if before.vitals.capillaryRefillSeconds != after.vitals.capillaryRefillSeconds { d.append(.vitalsCapillaryRefillSeconds(after.vitals.capillaryRefillSeconds)) }
        // MARCHState
        if before.march.hemorrhageIdentified != after.march.hemorrhageIdentified { d.append(.hemorrhageIdentified(after.march.hemorrhageIdentified)) }
        if before.march.hemorrhageAssessed != after.march.hemorrhageAssessed { d.append(.hemorrhageAssessed(after.march.hemorrhageAssessed)) }
        if before.march.hemorrhageLocation != after.march.hemorrhageLocation { d.append(.hemorrhageLocation(after.march.hemorrhageLocation)) }
        if before.march.hemorrhageIntervention != after.march.hemorrhageIntervention { d.append(.hemorrhageIntervention(after.march.hemorrhageIntervention)) }
        if before.march.hemorrhageEffective != after.march.hemorrhageEffective { d.append(.hemorrhageEffective(after.march.hemorrhageEffective)) }
        if before.march.airwayStatus != after.march.airwayStatus { d.append(.airwayStatus(after.march.airwayStatus)) }
        if before.march.airwayIntervention != after.march.airwayIntervention { d.append(.airwayIntervention(after.march.airwayIntervention)) }
        if before.march.respirationStatus != after.march.respirationStatus { d.append(.respirationStatus(after.march.respirationStatus)) }
        if before.march.respirationIntervention != after.march.respirationIntervention { d.append(.respirationIntervention(after.march.respirationIntervention)) }
        if before.march.breathSounds != after.march.breathSounds { d.append(.breathSounds(after.march.breathSounds)) }
        if before.march.pulseStatus != after.march.pulseStatus { d.append(.pulseStatus(after.march.pulseStatus)) }
        if before.march.skinSigns != after.march.skinSigns { d.append(.skinSigns(after.march.skinSigns)) }
        if before.march.circulationIntervention != after.march.circulationIntervention { d.append(.circulationIntervention(after.march.circulationIntervention)) }
        if before.march.consciousness != after.march.consciousness { d.append(.consciousness(after.march.consciousness)) }
        if before.march.pupilResponse != after.march.pupilResponse { d.append(.pupilResponse(after.march.pupilResponse)) }
        if before.march.hypothermiaPrevention != after.march.hypothermiaPrevention { d.append(.hypothermiaPrevention(after.march.hypothermiaPrevention)) }
        // PAWS
        if before.paws.pain != after.paws.pain { d.append(.pawsPain(after.paws.pain)) }
        if before.paws.antibiotics != after.paws.antibiotics { d.append(.pawsAntibiotics(after.paws.antibiotics)) }
        if before.paws.wounds != after.paws.wounds { d.append(.pawsWounds(after.paws.wounds)) }
        if before.paws.splinting != after.paws.splinting { d.append(.pawsSplinting(after.paws.splinting)) }
        return d
    }

    private nonisolated static func appendCollectionDiff<Element: Equatable>(
        _ before: [Element], _ after: [Element], into d: inout [PatientStateDelta],
        append: (Element) -> PatientStateDelta, set: ([Element]) -> PatientStateDelta
    ) {
        guard before != after else { return }
        if after.count >= before.count && Array(after.prefix(before.count)) == before {
            for element in after.suffix(after.count - before.count) { d.append(append(element)) }
        } else {
            d.append(set(after))
        }
    }
}
```

Also refactor the engine's existing `apply` to reuse `applyWrite` (behavior identical — same field assignments + the existing `timestampLastUpdate = Date()`):

```swift
// PatientStateEngine.swift — replace the body of apply(_:to:) lines 130-152
public func apply(_ writes: [PatientStateFieldWrite], to patientId: String) {
    guard !writes.isEmpty else { return }
    ensurePatientExists(patientId)
    var p = patients[patientId]!
    for write in writes { Self.applyWrite(write, to: &p) }
    p.timestampLastUpdate = Date().timeIntervalSince1970
    patients[patientId] = p
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter PatientStateDiffTests`
Expected: PASS. Then full suite → 738 passing (732 + 6). The refactored `apply` keeps `PatientStateApplyTests` green.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateDiffTests.swift
git commit -m "feat(event-sourcing): total diff + applyDelta/applyWrite (inverse property proven)"
```

---

## Task A3: project(log) + dual-write in processTranscript + the equivalence test

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift` (add `project`)
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (add `log`, `snapshotLog()`, emit events in `processTranscript`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift`

**Interfaces:**
- Produces: `nonisolated static func project(_:) -> [String: PatientState]`; `public private(set) var log: EncounterLog` + `public func snapshotLog() -> EncounterLog`. `processTranscript` now appends `asrSegment` + `deterministicFact` events (still imperative state). Consumed by A5.
- Consumes: A1/A2.

- [ ] **Step 1: Write the failing test**

```swift
// Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

/// The de-risker: the fold of the log a transcript produced must equal the
/// imperative result, field-by-field (full ==), over the real scenario fixtures.
final class LogEquivalenceTests: XCTestCase {

    private func loadScenario(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "scenarios"),
            "Scenario fixture \(name).txt not found")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertFoldEqualsImperative(_ scenario: String) async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario(scenario)
        await engine.processTranscript(text)
        let imperative = await engine.snapshot()
        let log = await engine.snapshotLog()
        let projected = PatientStateEngine.project(log)
        XCTAssertEqual(projected, imperative, "fold != imperative for \(scenario)")
    }

    func testScenario1FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_1_gsw_thigh") }
    func testScenario2FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_2_blast_multi") }
    func testScenario3FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_3_mre_laceration") }
    func testScenario4FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_4_femur_fracture") }

    func testMultiChunkFoldEqualsImperative() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW upper right thigh.")
        await engine.processTranscript("Heart rate one ten.")
        await engine.processTranscript("Blood pressure ninety over sixty.")
        let imperative = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(projected, imperative)
    }

    func testProjectionIsIdempotent() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(try loadScenario("scenario_2_blast_multi"))
        let log = await engine.snapshotLog()
        XCTAssertEqual(PatientStateEngine.project(log), PatientStateEngine.project(log))
    }

    func testLogAccumulatesASRAndFactEvents() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Heart rate one ten.")
        let log = await engine.snapshotLog()
        XCTAssertTrue(log.events.contains { if case .asrSegment = $0 { return true }; return false })
        XCTAssertTrue(log.events.contains {
            if case .deterministicFact(let p) = $0, case .vitalsHR(110) = p.delta { return true }; return false
        })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter LogEquivalenceTests`
Expected: FAIL — `value of type 'PatientStateEngine' has no member 'snapshotLog'` / `no member 'project'`.

- [ ] **Step 3: Write minimal implementation**

Add `project` to `PatientStateProjection.swift`:

```swift
extension PatientStateEngine {
    /// Fold the log into per-patient state by replaying recorded deltas + operator
    /// writes in order. Pure: never re-runs extractors, never reads actor state.
    nonisolated static func project(_ log: EncounterLog) -> [String: PatientState] {
        var patients: [String: PatientState] = ["PATIENT_1": PatientState(patientId: "PATIENT_1")]
        func ensure(_ pid: String) {
            if patients[pid] == nil { patients[pid] = PatientState(patientId: pid) }
        }
        for event in log.events {
            switch event {
            case .asrSegment, .operatorRejectedFact, .lifecycle:
                continue
            case .deterministicFact(let p):
                ensure(p.patientId)
                var s = patients[p.patientId]!
                applyDelta(p.delta, to: &s)
                patients[p.patientId] = s
            case .operatorAcceptedFact(let p):
                ensure(p.patientId)
                guard let write = p.write else { continue }
                var s = patients[p.patientId]!
                applyWrite(write, to: &s)
                s.timestampLastUpdate = p.timestampUnix
                patients[p.patientId] = s
            }
        }
        return patients
    }
}
```

Add the log + event emission to `PatientStateEngine.swift`. Add stored properties near the existing state, a read accessor, and the emission in `processTranscript` (capture `before`, keep the existing loop, then emit). Replace `processTranscript` as follows:

```swift
// Add near `patients` / `currentPatientID`:
public private(set) var log = EncounterLog()
private var asrCount = 0
private var factCount = 0

public func snapshotLog() -> EncounterLog { log }

public func processTranscript(_ text: String, timestamp: Date = Date()) {
    let before = patients                               // A3: capture for the diff
    let normalized = normalizer.normalize(text)
    let sentences = tokenizer.tokenize(normalized)
    let unixTimestamp = timestamp.timeIntervalSince1970

    for sentence in sentences {
        if let newID = switcher.detectSwitch(in: sentence) {
            currentPatientID = newID
            ensurePatientExists(currentPatientID)
        }
        ensurePatientExists(currentPatientID)
        var patient = patients[currentPatientID]!
        if patient.timestampFirstMention == nil { patient.timestampFirstMention = unixTimestamp }
        patient.timestampLastUpdate = unixTimestamp
        let isNegated = negation.sentenceHasNegationMarker(sentence)
        let context = ExtractionContext(
            originalText: text, normalizedText: normalized, sentence: sentence,
            timestamp: timestamp, currentPatientID: currentPatientID, isNegated: isNegated)
        var current = patient
        for pass in passes { current = pass.apply(current, context: context) }
        patients[currentPatientID] = current
    }

    emitEvents(text: text, before: before, timestamp: unixTimestamp)   // A3 dual-write
    // A5 will append: patients = Self.project(log)
}

/// Emit the asrSegment + per-patient deterministicFact events for one transcript call.
private func emitEvents(text: String, before: [String: PatientState], timestamp: Double) {
    asrCount += 1
    let segId = "seg-\(asrCount)"
    log.append(.asrSegment(.init(
        id: segId, patientId: currentPatientID, timestampUnix: timestamp,
        text: text, backend: "engine", isFinal: true)))
    for (pid, after) in patients.sorted(by: { $0.key < $1.key }) {
        let beforeP = before[pid] ?? PatientState(patientId: pid)
        for delta in Self.diff(beforeP, after) {
            factCount += 1
            log.append(.deterministicFact(.init(
                id: "fact-\(factCount)", patientId: pid, timestampUnix: timestamp,
                delta: delta, evidenceIds: [segId], extractor: "deterministic")))
        }
    }
}
```

> Note the `.sorted` over patients makes event order deterministic across runs (dictionary iteration order is otherwise unspecified) — important for `EncounterLog` equality in later tests.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter LogEquivalenceTests`
Expected: PASS (7 tests). Full suite → 745 passing. **The four scenario equivalence tests are the gate for A5.** If any fails, the diff missed a field — fix `diff`/`applyDelta` (A2), do not proceed to A5.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
git commit -m "feat(event-sourcing): project(log) fold + transcript dual-write + equivalence gate (4 fixtures green)"
```

---

## Task A4: Operator-path dual-write (engine records accept/reject events)

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (add `recordOperatorAcceptedFact`, `recordOperatorRejectedFact`)
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (`acceptGraniteFact`/`rejectGraniteReviewItem` route to the engine methods)
- Test: `TCCC_IOSTests/EventSourcingApplyPathTests.swift` (new) + existing apply-path suites stay green

**Interfaces:**
- Produces (engine): `func recordOperatorAcceptedFact(write:factId:domain:field:rawValue:to:timestamp:)`, `func recordOperatorRejectedFact(factId:domain:field:rawValue:to:timestamp:)`. In A4 these imperatively apply (accepted) + append the event (shadow). A5 adds the reproject.
- Consumes: A1–A3.

- [ ] **Step 1: Write the failing test** (app target)

```swift
// TCCC_IOSTests/EventSourcingApplyPathTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class EventSourcingApplyPathTests: XCTestCase {

    // Setup mirrors the existing GraniteApplyPathTests verbatim (AppState(),
    // GraniteValidationResult has NO isAccepted param — it's computed from errors).
    private func fact(_ field: String, _ value: String, domain: String = "vitals") -> GraniteCandidateFact {
        GraniteCandidateFact(id: "fact-1", patientId: "PATIENT_1", domain: domain,
                             field: field, value: value, evidenceIds: ["seg-1"], confidence: .medium)
    }
    private func validation(_ facts: [GraniteCandidateFact]) -> GraniteValidationResult {
        GraniteValidationResult(acceptedFacts: facts, conflicts: [], errors: [])
    }
    private func item(_ f: GraniteCandidateFact) -> GraniteReviewItem {
        GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: f.patientId,
                candidateFacts: [f], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([f]))
    }

    func testAcceptedFactStillMutatesEngine() async throws {
        let state = AppState()
        let f = fact("heartRate", "120")
        let it = item(f)
        state.graniteReviewQueue = [it]
        let accepted = OperatorAcceptedFact(f, from: it.validation)!
        await state.acceptGraniteFact(accepted, in: it)
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 120)
    }

    func testAcceptedFactAppendsOperatorAcceptedEvent() async throws {
        let state = AppState()
        let f = fact("heartRate", "120")
        let it = item(f)
        state.graniteReviewQueue = [it]
        let accepted = OperatorAcceptedFact(f, from: it.validation)!
        await state.acceptGraniteFact(accepted, in: it)
        let log = await state.engine.snapshotLog()
        XCTAssertTrue(log.events.contains {
            if case .operatorAcceptedFact(let p) = $0, p.field == "heartRate",
               let w = p.write, w == .heartRate(120) { return true }
            return false
        })
    }
}
```

> Setup verified against `TCCC_IOSTests/GraniteApplyPathTests.swift`: `AppState()` (no `previewLoaded`), `GraniteValidationResult(acceptedFacts:conflicts:errors:)` (computed `isAccepted`), `state.engine`/`state.primaryPatient` reachable via `@testable import`. `import TCCCExtractor` is required to name `EncounterEvent`.

- [ ] **Step 2: Run test to verify it fails**

Run (app target): `xcodebuild test ... -only-testing:TCCC_IOSTests/EventSourcingApplyPathTests/testAcceptedFactAppendsOperatorAcceptedEvent`
Expected: FAIL — no `operatorAcceptedFact` event is appended yet.

- [ ] **Step 3: Write minimal implementation**

Engine methods (append `PatientStateEngine.swift`):

```swift
private var opCount = 0

/// Record + apply an operator-accepted fact. A4: imperative apply (reuse apply) +
/// append the event. A5 adds `patients = Self.project(log)` after the append.
public func recordOperatorAcceptedFact(write: PatientStateFieldWrite, factId: String?,
    domain: String, field: String, rawValue: String?, to patientId: String,
    timestamp: Date = Date()) {
    let unix = timestamp.timeIntervalSince1970
    apply([write], to: patientId)                              // imperative (A4)
    opCount += 1
    log.append(.operatorAcceptedFact(.init(
        id: "op-\(opCount)", patientId: patientId, timestampUnix: unix,
        write: write, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
}

/// Record an operator rejection (audit only — never mutates state).
public func recordOperatorRejectedFact(factId: String?, domain: String, field: String,
    rawValue: String?, to patientId: String, timestamp: Date = Date()) {
    opCount += 1
    log.append(.operatorRejectedFact(.init(
        id: "op-\(opCount)", patientId: patientId, timestampUnix: timestamp.timeIntervalSince1970,
        write: nil, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
}
```

Route the app's accept path through it. In `GraniteReviewQueue.swift`, replace the `.mutation` arm and the reject method:

```swift
// acceptGraniteFact — the FieldRouter switch:
switch FieldRouter.route(domain: fact.domain, field: fact.field, value: fact.value) {
case .mutation(let write):
    await engine.recordOperatorAcceptedFact(
        write: write, factId: fact.id, domain: fact.domain, field: fact.field,
        rawValue: fact.value, to: fact.patientId)
    await refreshPatientSnapshot()
    appendSystem("GRANITE ACCEPTED · \(fact.field) = \(fact.value ?? "")")
case .rejected(let reason):
    await engine.recordOperatorRejectedFact(
        factId: fact.id, domain: fact.domain, field: fact.field,
        rawValue: fact.value, to: fact.patientId)
    appendSystem("GRANITE REJECTED · \(fact.field) · \(reason)")
}
```

```swift
// rejectGraniteReviewItem — also record a rejection event per candidate fact (audit):
func rejectGraniteReviewItem(_ item: GraniteReviewItem) {
    let pid = primaryPatient?.patientId ?? "PATIENT_1"
    Task { [engine] in
        for fact in item.patch.candidateFacts where fact.patientId == pid {
            await engine.recordOperatorRejectedFact(
                factId: fact.id, domain: fact.domain, field: fact.field, rawValue: fact.value, to: pid)
        }
    }
    graniteReviewQueue.removeAll { $0.id == item.id }
    appendSystem("GRANITE REVIEW REJECTED · discarded")
}
```

> Keep the existing foreign-patient guard and the contradiction→conflict early-return in `acceptGraniteFact` exactly as they are — they run *before* the FieldRouter switch and must be unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: the two new app tests (method-level), then the existing apply-path suites:
```
-only-testing:TCCC_IOSTests/EventSourcingApplyPathTests/testAcceptedFactStillMutatesEngine
-only-testing:TCCC_IOSTests/EventSourcingApplyPathTests/testAcceptedFactAppendsOperatorAcceptedEvent
-only-testing:TCCC_IOSTests/GraniteApplyPathTests   (full suite form)
-only-testing:TCCC_IOSTests/GraniteConflictRoutingTests
```
Expected: PASS. Plus full TCCCKit suite still 745. (App total stays 67 + new methods.)

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOSTests/EventSourcingApplyPathTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(event-sourcing): operator accept/reject record events (dual-write, engine-mediated)"
```

---

## Task A5: The flip — `patients = project(log)` becomes canonical

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (one line each in `processTranscript`, `recordOperatorAcceptedFact`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift` (add a post-flip canonical assertion); all existing suites are the real gate.

**Interfaces:** No signature changes. Behavior: `snapshot()` now reflects `project(log)`.

- [ ] **Step 1: Write the failing test**

```swift
// Append to LogEquivalenceTests.swift
func testAfterFlipSnapshotIsTheProjection() async throws {
    let engine = PatientStateEngine.standard()
    await engine.processTranscript(try loadScenario("scenario_1_gsw_thigh"))
    let snap = await engine.snapshot()
    let projected = PatientStateEngine.project(await engine.snapshotLog())
    XCTAssertEqual(snap, projected)            // snapshot IS the fold, not a parallel imperative copy
    // And a known field still lands (guards against an all-empty projection passing trivially):
    XCTAssertEqual(snap["PATIENT_1"]?.vitals.hr, 110)
}
```

> This passes trivially before the flip (both equal the imperative result) — its purpose is to lock the post-flip invariant and fail loudly if a later change desyncs `snapshot()` from `project(log)`. The binding gate for A5 is that **all 745 TCCCKit + all app tests stay green** once the imperative assignment is removed.

- [ ] **Step 2: Run the full suites (pre-change baseline)**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → 746 (745 + 1 new, all green pre-flip).

- [ ] **Step 3: Make the flip**

In `processTranscript`, after `emitEvents(...)`, add the canonical assignment:

```swift
    emitEvents(text: text, before: before, timestamp: unixTimestamp)
    patients = Self.project(log)              // ← FLIP: state flows from the log
}
```

In `recordOperatorAcceptedFact`, replace the imperative `apply([write], ...)` with append-then-project so the operator change also flows from the log:

```swift
public func recordOperatorAcceptedFact(write: PatientStateFieldWrite, factId: String?,
    domain: String, field: String, rawValue: String?, to patientId: String,
    timestamp: Date = Date()) {
    ensurePatientExists(patientId)
    let unix = timestamp.timeIntervalSince1970
    opCount += 1
    log.append(.operatorAcceptedFact(.init(
        id: "op-\(opCount)", patientId: patientId, timestampUnix: unix,
        write: write, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
    patients = Self.project(log)              // ← FLIP
}
```

> `ensurePatientExists` before projecting is harmless (project re-creates the default base anyway) but keeps `currentPatientID`/row bookkeeping consistent for any reader between calls.

- [ ] **Step 4: Run tests to verify they pass**

Run: full TCCCKit suite `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → **746 green**. Then the full app suite (or at least `GraniteApplyPathTests`, `GraniteConflictRoutingTests`, `EventSourcingApplyPathTests`, `EndToEnd`-style app tests). All green.
**Verification of the "no test asserts old internals" check (Global Constraint):** grep the test targets for any assertion on direct post-`apply` `timestampLastUpdate` exact values or on imperative-only side effects; there should be none (apply-path tests assert field values + conflict routing, not internal timestamps). Record the grep result in the task report.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
git commit -m "feat(event-sourcing): flip canonical — PatientState is now project(log)"
```

---

## Task A6: Surface real evidence linkage (retire the `evidenceIds: []` stopgap)

**Files:**
- Modify: `TCCC_IOS/Intelligence/DeterministicFactProjector.swift` (project from the engine log with real evidence)
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (`runGraniteHotSeatReview` / `currentEngineValue` source facts from the log)
- Test: `TCCC_IOSTests/EvidenceLinkageTests.swift` (new)

**Interfaces:**
- Produces (engine, TCCCExtractor): `nonisolated static func deterministicFacts(from log: EncounterLog) -> [(patientId: String, domain: String, field: String, value: String, evidenceIds: [String])]` — derives the latest value per (patientId, domain, field) from `deterministicFact` events, carrying their `evidenceIds`. (Add to `PatientStateProjection.swift`.)
- Consumes: A1–A5.

> Mapping `PatientStateDelta` → the `(domain, field, value)` vocabulary that `GraniteSchemaValidator.allowedFields` uses is the substance here. Only the DD-1380-bindable subset that `DeterministicFactProjector` already emits needs mapping (heartRate, spo2, respiratoryRate, bloodPressure, hemorrhageLocation, hemorrhageIntervention, airwayIntervention, consciousness, hypothermiaPrevention, pain, antibiotic). Deltas outside that subset are ignored for the packet (they still live in the log as audit).

- [ ] **Step 1: Write the failing test**

```swift
// TCCC_IOSTests/EvidenceLinkageTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class EvidenceLinkageTests: XCTestCase {

    func testDeterministicFactsCarryRealSegmentEvidence() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Heart rate one ten.")
        let log = await engine.snapshotLog()
        let facts = PatientStateEngine.deterministicFacts(from: log)
        let hr = try XCTUnwrap(facts.first { $0.domain == "vitals" && $0.field == "heartRate" })
        XCTAssertEqual(hr.value, "110")
        XCTAssertFalse(hr.evidenceIds.isEmpty, "evidence must trace to an asrSegment id")
        XCTAssertTrue(hr.evidenceIds.allSatisfy { $0.hasPrefix("seg-") })
    }

    func testProjectorEmitsNonEmptyEvidenceFromLog() async throws {
        let state = AppState()
        await state.engine.processTranscript("BP ninety over sixty.")
        let facts = await state.deterministicFactsForPacket()   // new app accessor over the log
        XCTAssertTrue(facts.contains { $0.field == "bloodPressure" && !$0.evidenceIds.isEmpty })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:TCCC_IOSTests/EvidenceLinkageTests/testDeterministicFactsCarryRealSegmentEvidence`
Expected: FAIL — `no member 'deterministicFacts'`.

- [ ] **Step 3: Write minimal implementation**

Add the log→facts derivation (TCCCExtractor, `PatientStateProjection.swift`):

```swift
extension PatientStateEngine {
    public struct DerivedFact: Sendable, Equatable {
        public let patientId: String, domain: String, field: String, value: String
        public let evidenceIds: [String]
    }
    /// Latest (domain, field) value per patient from deterministicFact events, with
    /// the evidenceIds of the event that set it. Only the DD-1380-bindable subset
    /// that maps to the GraniteSchemaValidator vocabulary is surfaced.
    nonisolated static func deterministicFacts(from log: EncounterLog) -> [DerivedFact] {
        var latest: [String: DerivedFact] = [:]   // key: "pid|domain|field"
        for case .deterministicFact(let p) in log.events {
            guard let mapped = vocabulary(for: p.delta) else { continue }
            let key = "\(p.patientId)|\(mapped.domain)|\(mapped.field)"
            latest[key] = DerivedFact(patientId: p.patientId, domain: mapped.domain,
                field: mapped.field, value: mapped.value, evidenceIds: p.evidenceIds)
        }
        return Array(latest.values).sorted { ($0.field) < ($1.field) }
    }

    /// Map a delta to the (domain, field, value) packet vocabulary, or nil if the
    /// delta is not a DD-1380-bindable fact.
    private nonisolated static func vocabulary(for delta: PatientStateDelta) -> (domain: String, field: String, value: String)? {
        switch delta {
        case .vitalsHR(let v?):                 return ("vitals", "heartRate", String(v))
        case .vitalsSpO2(let v?):               return ("vitals", "spo2", String(v))
        case .vitalsRR(let v?):                 return ("vitals", "respiratoryRate", String(v))
        case .vitalsBP(let v?):                 return ("vitals", "bloodPressure", "\(v.systolic)/\(v.diastolic)")
        case .hemorrhageLocation(let v?):       return ("march", "hemorrhageLocation", v)
        case .hemorrhageIntervention(let v?):   return ("march", "hemorrhageIntervention", v)
        case .airwayIntervention(let v?):       return ("march", "airwayIntervention", v)
        case .consciousness(let v?):            return ("march", "consciousness", v)
        case .hypothermiaPrevention(let v?):    return ("march", "hypothermiaPrevention", v)
        case .pawsPain(let v?):                 return ("paws", "pain", v)
        case .pawsAntibiotics(let v?):          return ("paws", "antibiotic", v)
        default:                                return nil
        }
    }
}
```

Add an app accessor + repoint the packet builder. In `GraniteReviewQueue.swift`:

```swift
/// Deterministic facts for the hot-seat packet, sourced from the engine log so
/// each fact carries real asrSegment evidence (replaces the evidenceIds:[] stopgap).
func deterministicFactsForPacket() async -> [DeterministicFact] {
    let derived = PatientStateEngine.deterministicFacts(from: await engine.snapshotLog())
    return derived.enumerated().map { idx, f in
        DeterministicFact(id: "det-\(idx + 1)", patientId: f.patientId, domain: f.domain,
            field: f.field, value: f.value, evidenceIds: f.evidenceIds,
            extractor: "deterministic", confidence: .high)
    }
}
```

Then in `runGraniteHotSeatReview`, replace the `deterministicFacts:` argument:

```swift
        let packet = HotSeatPacketBuilder.build(
            activePatientId: activePatientId,
            segments: segments,
            deterministicFacts: await deterministicFactsForPacket(),
            date: Date()
        )
```

> Leave `DeterministicFactProjector.project(_:)` in place for now (some call sites — e.g. `currentEngineValue` — read the current snapshot synchronously). Update its doc-comment to drop the "evidence is best-effort empty — gated on the future EncounterEvent log" sentence, since the log now exists and the packet path uses it. The stopgap that the spec targets is the *packet's* empty evidence; that is now retired.

- [ ] **Step 4: Run to verify it passes**

Run the two `EvidenceLinkageTests` methods + the existing Granite suites. Expected: PASS. Full TCCCKit suite gains the `deterministicFacts(from:)` coverage if you add a TCCCExtractor test too (optional). App suite green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOS/Intelligence/DeterministicFactProjector.swift TCCC_IOSTests/EvidenceLinkageTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(event-sourcing): packet facts carry real segment evidence from the log (retire evidenceIds:[] stopgap)"
```

---

## Task A7: Invariant test — LLM-never-mutates survives the retrofit

**Files:**
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift` (new) + `TCCC_IOSTests/InvariantStructureTests.swift` (new, source-grep)

**Interfaces:** Tests only. No production change.

- [ ] **Step 1: Write the failing test**

```swift
// Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class EngineInvariantTests: XCTestCase {

    /// An operatorAcceptedFact event is the ONLY way a non-extraction value enters
    /// the projection. A rejected event must never affect projected state.
    func testRejectedFactNeverAffectsProjection() {
        var log = EncounterLog()
        log.append(.operatorRejectedFact(.init(id: "op-1", patientId: "PATIENT_1",
            timestampUnix: 1, write: .heartRate(200), sourceFactId: "g", domain: "vitals",
            field: "heartRate", rawValue: "200")))
        let projected = PatientStateEngine.project(log)
        XCTAssertNil(projected["PATIENT_1"]?.vitals.hr, "a rejected fact must not mutate state")
    }

    func testAcceptedFactWithNilWriteIsInert() {
        var log = EncounterLog()
        log.append(.operatorAcceptedFact(.init(id: "op-1", patientId: "PATIENT_1",
            timestampUnix: 1, write: nil, sourceFactId: "g", domain: "vitals",
            field: "heartRate", rawValue: "x")))
        XCTAssertNil(PatientStateEngine.project(log)["PATIENT_1"]?.vitals.hr)
    }

    /// asrSegment events alone never set state — only their derived deterministicFact
    /// deltas do. A log of bare asrSegments projects to the default base.
    func testBareASRSegmentsProjectToDefault() {
        var log = EncounterLog()
        log.append(.asrSegment(.init(id: "seg-1", patientId: "PATIENT_1", timestampUnix: 1,
            text: "heart rate two hundred", backend: "engine", isFinal: true)))
        XCTAssertEqual(PatientStateEngine.project(log)["PATIENT_1"], PatientState(patientId: "PATIENT_1"))
    }
}
```

```swift
// TCCC_IOSTests/InvariantStructureTests.swift — structural source check
import XCTest

final class InvariantStructureTests: XCTestCase {
    /// There must be exactly ONE production call that records an operator-accepted
    /// fact into the engine, and it must be reached only from the FieldRouter
    /// `.mutation` arm. Guards against a future direct engine.apply from an LLM path.
    func testSingleOperatorAcceptCallSite() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()   // repo/TCCC_IOSTests/.. = repo
        let intel = root.appendingPathComponent("TCCC_IOS/Intelligence")
        let files = try FileManager.default.contentsOfDirectory(at: intel, includingPropertiesForKeys: nil)
        var acceptCalls = 0
        for f in files where f.pathExtension == "swift" {
            let src = try String(contentsOf: f, encoding: .utf8)
            acceptCalls += src.components(separatedBy: "recordOperatorAcceptedFact").count - 1
        }
        XCTAssertEqual(acceptCalls, 1, "exactly one production accept-record call site expected")
    }
}
```

> The implementer verifies the `#filePath`-relative traversal resolves to the repo root on this machine and on a fresh checkout (same pattern as `RubricDriftProtectionTests`); adjust the number of `deletingLastPathComponent()` hops to match the real test-file depth.

- [ ] **Step 2: Run to verify it fails / passes appropriately**

Run both suites. The TCCCKit invariant tests should PASS immediately (they assert already-true projection behavior — they lock it). The `InvariantStructureTests` should PASS with the A4 wiring (one call site). If `acceptCalls != 1`, investigate before proceeding.

- [ ] **Step 3: (No production code expected.)** If `testSingleOperatorAcceptCallSite` fails because the count is 0 or >1, fix the wiring (there must be exactly one `recordOperatorAcceptedFact` call in `Intelligence/`), not the test.

- [ ] **Step 4: Run to verify pass**

Run: TCCCKit full suite + `-only-testing:TCCC_IOSTests/InvariantStructureTests/testSingleOperatorAcceptCallSite`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift TCCC_IOSTests/InvariantStructureTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "test(event-sourcing): lock LLM-never-mutates invariant (projection + single accept call site)"
```

---

## Task A8: Polish — lifecycle event, enum-sync regression, log-string consistency

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (emit `encounterStarted` on init)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift` (add enum-sync + lifecycle tests)

**Interfaces:** Engine seeds an `encounterStarted` lifecycle event at init so a fresh encounter's log is never empty.

- [ ] **Step 1: Write the failing test**

```swift
// Append to EngineInvariantTests.swift
func testFreshEngineLogStartsWithEncounterStarted() async {
    let engine = PatientStateEngine.standard()
    let log = await engine.snapshotLog()
    XCTAssertEqual(log.events.first.flatMap { e -> Bool? in
        if case .lifecycle(let p) = e { return p.kind == .encounterStarted }; return nil
    }, true)
}

/// Every PatientStateFieldWrite case must be representable as a PatientStateDelta,
/// so an operator accept and the projection share one vocabulary. Fails if a future
/// write case is added without a matching delta mapping.
func testEveryFieldWriteMapsToADelta() {
    let writes: [PatientStateFieldWrite] = [
        .heartRate(1), .spo2(1), .respiratoryRate(1),
        .bloodPressure(systolic: 1, diastolic: 1, palpated: false),
        .hemorrhageLocation("x"), .hemorrhageIntervention("x"), .airwayIntervention("x"),
        .consciousness("x"), .hypothermiaPrevention("x"), .pain("x"), .antibiotics("x"),
    ]
    // Applying a write and diffing must yield at least one delta — proving the field
    // is reachable through the delta vocabulary.
    for w in writes {
        var s = PatientState(patientId: "PATIENT_1")
        PatientStateEngine.applyWrite(w, to: &s)
        let deltas = PatientStateEngine.diff(PatientState(patientId: "PATIENT_1"), s)
        XCTAssertFalse(deltas.isEmpty, "write \(w) produced no delta — vocabulary drift")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `--filter EngineInvariantTests`. Expected: `testFreshEngineLogStartsWithEncounterStarted` FAILS (log empty at init).

- [ ] **Step 3: Write minimal implementation**

In `PatientStateEngine.init`, seed the lifecycle event (after the PATIENT_1 row is created):

```swift
        self.patients["PATIENT_1"] = PatientState(patientId: "PATIENT_1")
        self.log.append(.lifecycle(.init(
            id: "lc-1", patientId: "PATIENT_1", timestampUnix: 0, kind: .encounterStarted)))
```

> `timestampUnix: 0` keeps init deterministic (no `Date()` in the constructor). The equivalence tests are unaffected — `project` ignores `lifecycle` events, and `snapshotLog()` consumers in A3/A5 already tolerate a leading lifecycle event (the asr/fact assertions use `contains`).

- [ ] **Step 4: Run to verify pass**

Run: `--filter EngineInvariantTests` → PASS. Then **the full TCCCKit suite** `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → all green (the leading lifecycle event must not break A3/A5 equivalence — confirm). Then the **full app suite** on the working destination → green.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift
git commit -m "feat(event-sourcing): seed encounterStarted lifecycle event + enum-sync regression"
```

---

## Final verification (before whole-branch review)

- [ ] Full TCCCKit suite green (`swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`) — expect ~746+ tests.
- [ ] Full app suite green on `-destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E'`.
- [ ] Acceptance gate (spec §8): equivalence holds on all 4 fixtures; diff inverse holds per field family; one operator-accept call site; no `evidenceIds: []` in the packet path; `snapshot() == project(log)`.
- [ ] Whole-branch review on opus (superpowers:requesting-code-review): re-verify the invariant survives and the flip preserves the engine contract; triage carried minors from `.superpowers/sdd/progress.md`.
- [ ] Then superpowers:finishing-a-development-branch (merge locally on the user's say-so).
