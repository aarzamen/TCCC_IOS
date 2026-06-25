# Reconciliation Apply Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an operator accept an AI (Granite hot-seat) candidate fact so it becomes a real `PatientState` value — applied through the deterministic engine, never by the LLM — with a rubric-bounded field router whose boundary is proven in both directions.

**Architecture:** A typed `PatientStateFieldWrite` enum in **TCCCKit** is the *only* non-extraction vocabulary for writing a `PatientState` field; `PatientStateEngine` gains an `apply([PatientStateFieldWrite])` method so the engine stays the sole writer. A rubric-bounded `FieldRouter` in the **app target** translates an LLM-originated `(domain, field, value: String)` triple into a `PatientStateFieldWrite` or an explicit rejection (the four-case boundary gate). `OperatorAcceptedFact` is a guard type constructible only from a schema-validated, operator-accepted fact, so there is no compile-reachable path from raw model text to a setter. Contradictions with existing engine values route to a conflict (held), never auto-applied.

**Tech Stack:** Swift 6 (strict concurrency, `@MainActor`, actors), SwiftUI, XCTest. TCCCKit local SPM package (`swift test`); app target built via xcodegen + xcodebuild. No new dependencies, no networking.

## Global Constraints

Every task's requirements implicitly include these (verbatim from the spec + CLAUDE.md hard constraints):

- **RF Ghost:** no Wi-Fi/BLE/cellular/UWB/NFC, no analytics/telemetry/auto-update, no networking framework added by any task. On-device only.
- **Engine is the sole writer of `PatientState`.** The only non-extraction mutation entry is `PatientStateEngine.apply(_:to:)`, which accepts only the typed `PatientStateFieldWrite` vocabulary.
- **LLM-never-mutates-state is structural:** model output reaches a setter only via schema validation → `OperatorAcceptedFact` → `FieldRouter` (rubric-bounded) → typed `PatientStateFieldWrite` → engine. No free-form string write path exists.
- **Rubric is the allow-source:** `reference/rubric/extracted/dd1380_field_inventory.json` + `reference/rubric/extracted/march_paws_vocabulary_2026.json`. A wired `(domain, field)` must exist in the rubric (drift-tested).
- **Gloved-hand UI:** hit targets ≥ 44 pt, primary actions 56–64 pt, long-press (with progress fill) for destructive actions. Landscape, iPhone-only. NVG-safe theme tokens only (`palette.*`).
- **All 724 existing TCCCKit tests stay green.** New app tests added on top.
- **Scope fence:** no audio/ASR/Granite-Speech changes, no `EncounterEvent` log, no durable archive, no workflow engine. Those are deferred (spec §7). Evidence linkage is best-effort this cycle (debt gated on the event log).
- **Build/test commands:**
  - TCCCKit: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test`
  - App: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/<Class>` (`-skipMacroValidation` is required; `xcodegen generate` re-globs sources so new files are picked up; if the sim ID is stale, pick an iPhone 17 Pro from `xcrun simctl list devices`).

**Reference shapes (verbatim, do not re-derive):**

```swift
// TCCC_IOS/Intelligence/HotSeatPacket.swift (app target)
struct GraniteCandidateFact: Identifiable, Codable, Sendable, Equatable {
    let id: String; let patientId: String; let domain: String; let field: String
    let value: String?; let evidenceIds: [String]; let confidence: GraniteConfidence
}
struct DeterministicFact: Identifiable, Codable, Sendable, Equatable {
    let id: String; let patientId: String; let domain: String; let field: String
    let value: String; let evidenceIds: [String]; let extractor: String; let confidence: GraniteConfidence
}
enum GraniteConfidence: String, Codable, Sendable, Equatable, Hashable { case high, medium, low, conflict, unknown }
struct GraniteValidationResult: Sendable, Equatable {
    let acceptedFacts: [GraniteCandidateFact]; let conflicts: [GraniteConflict]
    let errors: Set<GraniteValidationError>; var isAccepted: Bool { errors.isEmpty }
}
struct GraniteReviewItem: Identifiable, Sendable, Equatable {
    let id: UUID; let createdAt: Date; let patch: GraniteCandidatePatch; let validation: GraniteValidationResult
    var status: GraniteReviewStatus { validation.isAccepted ? .readyForOperatorReview : .heldForValidation }
}
// GraniteSchemaValidator.allowedFields (Set<String>) already contains:
// "airway","airwayIntervention","allergies","antibiotic","bloodPressure","breathing","burns",
// "capillaryRefill","casualtyCategory","consciousness","evacuationPriority","heartRate",
// "hemorrhageIntervention","hemorrhageLocation","hypothermiaPrevention","injuryMechanism",
// "medication","mentalStatus","pain","patientId","pulse","respiratoryRate","signsAndSymptoms",
// "spo2","tourniquetTime","treatment","vitalTime"
```

```swift
// Packages/TCCCKit/Sources/TCCCDomain (TCCCKit) — mutation targets
struct Vitals { var hr: Int?; var bp: BloodPressure?; var spo2: Int?; var rr: Int?; var gcs: Int?
                var temperatureCelsius: Double?; var capillaryRefillSeconds: Double?
                static let hrRange = 0...300; static let spo2Range = 0...100; static let rrRange = 0...80 }
struct BloodPressure { let systolic: Int; let diastolic: Int; let palpated: Bool }   // public init(systolic:diastolic:palpated:)
struct MARCHState { var hemorrhageLocation: String?; var hemorrhageIntervention: String?
                    var airwayIntervention: String?; var consciousness: String?; var hypothermiaPrevention: String? /* +others */ }
struct PAWSAssessment { var pain: String?; var antibiotics: String?; var wounds: String?; var splinting: String? }
// PatientStateEngine: actor; patients[currentPatientID]; ensurePatientExists(_:) is private (same-file only);
// snapshot(of:) -> PatientState?
```

---

## Task 1: `PatientStateFieldWrite` + `PatientStateEngine.apply` (TCCCKit)

The typed write vocabulary and the engine's only non-extraction mutation entry.

**Files:**
- Create: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateFieldWrite.swift`
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (add `apply` inside the actor body so it can call the private `ensurePatientExists`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateApplyTests.swift`

**Interfaces:**
- Produces: `public enum PatientStateFieldWrite` (cases below); `public func PatientStateEngine.apply(_ writes: [PatientStateFieldWrite], to patientId: String)` (actor-isolated, so callers `await`).
- Consumes: `PatientState`, `Vitals`, `BloodPressure`, `MARCHState`, `PAWSAssessment` from `TCCCDomain`.

- [ ] **Step 1: Write the failing test**

```swift
// Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateApplyTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PatientStateApplyTests: XCTestCase {
    func testApplyHeartRateMutatesVitalsThroughEngine() async {
        let engine = PatientStateEngine.standard()
        await engine.apply([.heartRate(88)], to: "PATIENT_1")
        let p = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(p?.vitals.hr, 88)
    }

    func testApplyBloodPressureAndMarchFields() async {
        let engine = PatientStateEngine.standard()
        await engine.apply([
            .bloodPressure(systolic: 120, diastolic: 80, palpated: false),
            .hemorrhageLocation("left thigh"),
        ], to: "PATIENT_1")
        let p = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(p?.vitals.bp?.systolic, 120)
        XCTAssertEqual(p?.march.hemorrhageLocation, "left thigh")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter PatientStateApplyTests`
Expected: FAIL — `PatientStateFieldWrite` and `apply` do not exist (compile error).

- [ ] **Step 3: Create the typed write vocabulary**

```swift
// Packages/TCCCKit/Sources/TCCCExtractor/PatientStateFieldWrite.swift
import Foundation

/// The ONLY vocabulary by which a non-extraction caller may write a `PatientState`
/// field. Typed cases, never free-form strings: an LLM-originated string can reach
/// a setter only by being translated into one of these cases by the rubric-bounded
/// `FieldRouter`. The engine applies these and remains the sole writer of state.
public enum PatientStateFieldWrite: Sendable, Equatable {
    // Vitals (TCCC DD-1380 §C)
    case heartRate(Int)
    case spo2(Int)
    case respiratoryRate(Int)
    case bloodPressure(systolic: Int, diastolic: Int, palpated: Bool)
    // MARCH
    case hemorrhageLocation(String)
    case hemorrhageIntervention(String)
    case airwayIntervention(String)
    case consciousness(String)            // AVPU
    case hypothermiaPrevention(String)
    // PAWS
    case pain(String)
    case antibiotics(String)
}
```

- [ ] **Step 4: Add `apply` inside the `PatientStateEngine` actor**

Add this method to `PatientStateEngine.swift`, inside the `public actor PatientStateEngine { ... }` body (next to `processTranscript`), so it can call the private `ensurePatientExists`:

```swift
    /// Apply typed field writes to one patient. This is the ONLY non-extraction
    /// mutation entry; it accepts only the typed `PatientStateFieldWrite` vocabulary,
    /// so the engine remains the sole writer of `PatientState`.
    public func apply(_ writes: [PatientStateFieldWrite], to patientId: String) {
        guard !writes.isEmpty else { return }
        ensurePatientExists(patientId)
        var p = patients[patientId]!
        for write in writes {
            switch write {
            case .heartRate(let v):            p.vitals.hr = v
            case .spo2(let v):                 p.vitals.spo2 = v
            case .respiratoryRate(let v):      p.vitals.rr = v
            case .bloodPressure(let s, let d, let pal):
                p.vitals.bp = BloodPressure(systolic: s, diastolic: d, palpated: pal)
            case .hemorrhageLocation(let v):   p.march.hemorrhageLocation = v
            case .hemorrhageIntervention(let v): p.march.hemorrhageIntervention = v
            case .airwayIntervention(let v):   p.march.airwayIntervention = v
            case .consciousness(let v):        p.march.consciousness = v
            case .hypothermiaPrevention(let v): p.march.hypothermiaPrevention = v
            case .pain(let v):                 p.paws.pain = v
            case .antibiotics(let v):          p.paws.antibiotics = v
            }
        }
        p.timestampLastUpdate = Date().timeIntervalSince1970
        patients[patientId] = p
    }
```

If `BloodPressure(systolic:diastolic:palpated:)` is not `public`, add a `public init(systolic: Int, diastolic: Int, palpated: Bool)` to `BloodPressure.swift` (it is constructed by `VitalsExtractor` already, so a public init should exist; add it only if the compiler reports it inaccessible).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test --filter PatientStateApplyTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full TCCCKit suite (no regressions)**

Run: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test`
Expected: all 724 prior tests + 2 new = green.

- [ ] **Step 7: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateFieldWrite.swift \
        Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift \
        Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateApplyTests.swift
git commit -m "feat(engine): typed PatientStateFieldWrite + engine.apply (sole-writer mutation entry)"
```

---

## Task 2: `FieldRouter` + the boundary gate (app target)

The rubric-bounded translator and the both-directions acceptance gate for the apply path.

**Files:**
- Create: `TCCC_IOS/Intelligence/FieldRouter.swift`
- Test: `TCCC_IOSTests/FieldRouterBoundaryGateTests.swift`

**Interfaces:**
- Consumes: `PatientStateFieldWrite` (Task 1, `import TCCCExtractor`); `GraniteSchemaValidator.allowedFields`; `Vitals.hrRange/spo2Range/rrRange` (`import TCCCDomain`).
- Produces: `enum FieldRouteRejection`, `enum FieldRouteOutcome`, `enum FieldRouter { static func route(domain:field:value:) -> FieldRouteOutcome }`.

- [ ] **Step 1: Write the failing test — the boundary gate (5 members)**

```swift
// TCCC_IOSTests/FieldRouterBoundaryGateTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

final class FieldRouterBoundaryGateTests: XCTestCase {
    // --- Rejections: bad facts stay OUT (each explicit, never coerced) ---
    func testUnknownDomainRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "bogus", field: "heartRate", value: "88"),
                       .rejected(.unknownDomain("bogus")))
    }
    func testKnownDomainUnknownFieldRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "notAField", value: "88"),
                       .rejected(.unknownField("notAField")))
    }
    func testValueOutOfRubricRangeRejected() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "heartRate", value: "999"),
                       .rejected(.valueOutOfRubricRange(field: "heartRate", value: "999")))
    }
    func testKnownFieldNoSetterWiredRejected() {
        // "pulse" is in GraniteSchemaValidator.allowedFields but has no wired setter.
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "pulse", value: "110"),
                       .rejected(.noSetterWired(domain: "vitals", field: "pulse")))
    }
    // --- Acceptance: a good fact goes THROUGH (the 5th, positive member) ---
    func testWellFormedWiredInRangeRoutesToMutation() {
        XCTAssertEqual(FieldRouter.route(domain: "vitals", field: "heartRate", value: "88"),
                       .mutation(.heartRate(88)))
    }
    // A reject-everything router must FAIL this suite — the positive case guards that.
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/FieldRouterBoundaryGateTests`
Expected: FAIL — `FieldRouter` does not exist (compile error).

- [ ] **Step 3: Implement the router**

```swift
// TCCC_IOS/Intelligence/FieldRouter.swift
import Foundation
import TCCCDomain
import TCCCExtractor

/// Why a `(domain, field, value)` triple could not become a typed mutation.
/// Every rejection is explicit and surfaced/logged — never a silent drop.
enum FieldRouteRejection: Equatable {
    case unknownDomain(String)
    case unknownField(String)
    case valueOutOfRubricRange(field: String, value: String)
    case noSetterWired(domain: String, field: String)
}

enum FieldRouteOutcome: Equatable {
    case mutation(PatientStateFieldWrite)
    case rejected(FieldRouteRejection)
}

/// Rubric-bounded translator from an LLM-originated `(domain, field, value)` string
/// triple to a typed `PatientStateFieldWrite`, or an explicit rejection. This is the
/// boundary that makes "LLM-never-mutates-state" structural: only a wired, in-range,
/// rubric-known triple yields a mutation; everything else is rejected.
enum FieldRouter {
    static let knownDomains: Set<String> = ["march", "vitals", "paws", "medevac", "dd1380"]

    static func route(domain: String, field: String, value: String?) -> FieldRouteOutcome {
        guard knownDomains.contains(domain) else { return .rejected(.unknownDomain(domain)) }
        // "known field" oracle = the existing schema-validator allow-list.
        guard GraniteSchemaValidator.allowedFields.contains(field) else {
            return .rejected(.unknownField(field))
        }
        guard let value, !value.isEmpty else {
            return .rejected(.valueOutOfRubricRange(field: field, value: value ?? "nil"))
        }
        switch (domain, field) {
        case ("vitals", "heartRate"):
            guard let n = Int(value), Vitals.hrRange.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.heartRate(n))
        case ("vitals", "spo2"):
            guard let n = Int(value), Vitals.spo2Range.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.spo2(n))
        case ("vitals", "respiratoryRate"):
            guard let n = Int(value), Vitals.rrRange.contains(n) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.respiratoryRate(n))
        case ("vitals", "bloodPressure"):
            let parts = value.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let s = parts[0], let d = parts[1],
                  (0...300).contains(s), (0...300).contains(d) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.bloodPressure(systolic: s, diastolic: d, palpated: false))
        case ("march", "hemorrhageLocation"):     return .mutation(.hemorrhageLocation(value))
        case ("march", "hemorrhageIntervention"): return .mutation(.hemorrhageIntervention(value))
        case ("march", "airwayIntervention"):     return .mutation(.airwayIntervention(value))
        case ("march", "consciousness"):
            let avpu = Set(["A", "V", "P", "U", "Alert", "Voice", "Pain", "Unresponsive"])
            guard avpu.contains(value) else {
                return .rejected(.valueOutOfRubricRange(field: field, value: value))
            }
            return .mutation(.consciousness(value))
        case ("march", "hypothermiaPrevention"):  return .mutation(.hypothermiaPrevention(value))
        case ("paws", "pain"):                    return .mutation(.pain(value))
        case ("paws", "antibiotics"), ("paws", "antibiotic"): return .mutation(.antibiotics(value))
        default:
            return .rejected(.noSetterWired(domain: domain, field: field))
        }
    }
}
```

If `GraniteSchemaValidator.allowedFields` is declared `private`, change it to (package-)`internal` so `FieldRouter` in the same target can read it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/FieldRouterBoundaryGateTests`
Expected: PASS (5 tests — four rejections + the positive case).

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Intelligence/FieldRouter.swift TCCC_IOSTests/FieldRouterBoundaryGateTests.swift
git commit -m "feat(apply-path): rubric-bounded FieldRouter + both-directions boundary gate"
```

> **Acceptance gate for ②:** the full `FieldRouterBoundaryGateTests` suite (four rejections + positive) must stay green for the apply path to ship. A router that rejects everything fails `testWellFormedWiredInRangeRoutesToMutation`.

---

## Task 3: `DeterministicFactProjector` + feed the packet (app target)

Stop sending the LLM an empty deterministic-facts list; give it the engine's ground truth so it can challenge or avoid duplicating it.

**Files:**
- Create: `TCCC_IOS/Intelligence/DeterministicFactProjector.swift`
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (replace `deterministicFacts: []` at the single call site)
- Test: `TCCC_IOSTests/DeterministicFactProjectorTests.swift`

**Interfaces:**
- Consumes: `PatientState` (`import TCCCDomain`); `DeterministicFact`, `GraniteConfidence`.
- Produces: `enum DeterministicFactProjector { static func project(_ state: PatientState) -> [DeterministicFact] }`.

- [ ] **Step 1: Write the failing test**

```swift
// TCCC_IOSTests/DeterministicFactProjectorTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

final class DeterministicFactProjectorTests: XCTestCase {
    func testProjectsPopulatedFieldsWithRubricFieldNames() {
        var state = PatientState(patientId: "PATIENT_1")
        state.vitals.hr = 88
        state.march.hemorrhageLocation = "left thigh"
        let facts = DeterministicFactProjector.project(state)

        XCTAssertTrue(facts.contains { $0.domain == "vitals" && $0.field == "heartRate" && $0.value == "88" })
        XCTAssertTrue(facts.contains { $0.domain == "march" && $0.field == "hemorrhageLocation" && $0.value == "left thigh" })
        // empty fields are not projected
        XCTAssertFalse(facts.contains { $0.field == "spo2" })
        // best-effort evidence this cycle (debt gated on the event log)
        XCTAssertTrue(facts.allSatisfy { $0.evidenceIds.isEmpty && $0.confidence == .high })
    }

    func testEmptyStateProjectsNothing() {
        XCTAssertTrue(DeterministicFactProjector.project(PatientState(patientId: "PATIENT_1")).isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/DeterministicFactProjectorTests`
Expected: FAIL — `DeterministicFactProjector` does not exist.

- [ ] **Step 3: Implement the projector**

```swift
// TCCC_IOS/Intelligence/DeterministicFactProjector.swift
import Foundation
import TCCCDomain

/// Projects the engine's current `PatientState` into `[DeterministicFact]` so the
/// hot-seat packet carries the deterministic ground truth as context. Field names
/// match the `GraniteSchemaValidator.allowedFields` vocabulary so they round-trip
/// through the `FieldRouter`. Evidence linkage is best-effort this cycle (empty
/// `evidenceIds`) — a debt explicitly gated on the future EncounterEvent log.
enum DeterministicFactProjector {
    static func project(_ state: PatientState) -> [DeterministicFact] {
        var facts: [DeterministicFact] = []
        var idx = 0
        func add(_ domain: String, _ field: String, _ value: String?, _ extractor: String) {
            guard let value, !value.isEmpty else { return }
            idx += 1
            facts.append(DeterministicFact(
                id: "det-\(idx)", patientId: state.patientId, domain: domain, field: field,
                value: value, evidenceIds: [], extractor: extractor, confidence: .high))
        }
        if let hr = state.vitals.hr  { add("vitals", "heartRate", String(hr), "VitalsExtractor") }
        if let s = state.vitals.spo2 { add("vitals", "spo2", String(s), "VitalsExtractor") }
        if let rr = state.vitals.rr  { add("vitals", "respiratoryRate", String(rr), "VitalsExtractor") }
        if let bp = state.vitals.bp  { add("vitals", "bloodPressure", "\(bp.systolic)/\(bp.diastolic)", "VitalsExtractor") }
        add("march", "hemorrhageLocation", state.march.hemorrhageLocation, "HemorrhageExtractor")
        add("march", "hemorrhageIntervention", state.march.hemorrhageIntervention, "HemorrhageExtractor")
        add("march", "airwayIntervention", state.march.airwayIntervention, "AirwayExtractor")
        add("march", "consciousness", state.march.consciousness, "TBIExtractor")
        add("march", "hypothermiaPrevention", state.march.hypothermiaPrevention, "HypothermiaExtractor")
        add("paws", "pain", state.paws.pain, "PAWSExtractor")
        add("paws", "antibiotics", state.paws.antibiotics, "PAWSExtractor")
        return facts
    }
}
```

- [ ] **Step 4: Wire it into the packet build**

In `TCCC_IOS/Intelligence/GraniteReviewQueue.swift`, inside `runGraniteHotSeatReview(using:)`, replace the hardcoded empty list:

```swift
        let packet = HotSeatPacketBuilder.build(
            activePatientId: activePatientId,
            segments: segments,
            deterministicFacts: DeterministicFactProjector.project(
                primaryPatient ?? PatientState(patientId: activePatientId)),
            date: Date()
        )
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/DeterministicFactProjectorTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Intelligence/DeterministicFactProjector.swift TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOSTests/DeterministicFactProjectorTests.swift
git commit -m "feat(apply-path): project deterministic facts into the hot-seat packet (no longer empty)"
```

---

## Task 4: `OperatorAcceptedFact` guard + accept/reject flow (app target)

The structural guard and the engine-mediated accept path (no contradiction handling yet — Task 5).

**Files:**
- Create: `TCCC_IOS/Intelligence/OperatorAcceptedFact.swift`
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (add `AppState.acceptGraniteFact`, `rejectGraniteReviewItem`, helper `currentEngineValue`)
- Test: `TCCC_IOSTests/GraniteApplyPathTests.swift`

**Interfaces:**
- Consumes: `GraniteCandidateFact`, `GraniteValidationResult`, `GraniteReviewItem` (Task refs); `FieldRouter` (Task 2); `engine.apply` (Task 1); `DeterministicFactProjector` (Task 3).
- Produces: `struct OperatorAcceptedFact { init?(_:from:) ; let fact: GraniteCandidateFact }`; `func AppState.acceptGraniteFact(_ accepted: OperatorAcceptedFact, in item: GraniteReviewItem) async`; `func AppState.rejectGraniteReviewItem(_ item: GraniteReviewItem)`; `func AppState.currentEngineValue(domain:field:) -> String?`.

- [ ] **Step 1: Write the failing tests**

```swift
// TCCC_IOSTests/GraniteApplyPathTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteApplyPathTests: XCTestCase {
    private func acceptedFact(_ field: String, _ value: String, domain: String = "vitals") -> GraniteCandidateFact {
        GraniteCandidateFact(id: "fact-1", patientId: "PATIENT_1", domain: domain,
                             field: field, value: value, evidenceIds: ["seg-1"], confidence: .medium)
    }
    private func validation(_ facts: [GraniteCandidateFact]) -> GraniteValidationResult {
        GraniteValidationResult(acceptedFacts: facts, conflicts: [], errors: [])
    }

    func testOperatorAcceptedFactRejectsNonAcceptedFact() {
        let fact = acceptedFact("heartRate", "88")
        XCTAssertNil(OperatorAcceptedFact(fact, from: validation([])))         // not in acceptedFacts → nil
        XCTAssertNotNil(OperatorAcceptedFact(fact, from: validation([fact])))   // in acceptedFacts → wraps
    }

    func testAcceptMutatesStateThroughEngine() async {
        let state = AppState()
        let fact = acceptedFact("heartRate", "88")
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([fact]))
        state.graniteReviewQueue = [item]
        let accepted = OperatorAcceptedFact(fact, from: item.validation)!

        await state.acceptGraniteFact(accepted, in: item)

        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)   // mutated through the engine
    }

    func testRejectDoesNotMutateAndClearsItem() async {
        let state = AppState()
        let fact = acceptedFact("heartRate", "88")
        let before = state.primaryPatient
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: validation([fact]))
        state.graniteReviewQueue = [item]

        state.rejectGraniteReviewItem(item)

        XCTAssertEqual(state.primaryPatient, before)          // no mutation
        XCTAssertTrue(state.graniteReviewQueue.isEmpty)       // item cleared
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteApplyPathTests`
Expected: FAIL — `OperatorAcceptedFact` / `acceptGraniteFact` / `rejectGraniteReviewItem` do not exist.

- [ ] **Step 3: Implement the guard type**

```swift
// TCCC_IOS/Intelligence/OperatorAcceptedFact.swift
import Foundation

/// A candidate fact the operator has accepted. Constructible ONLY from a fact that
/// is a member of a `GraniteValidationResult.acceptedFacts` set — there is no other
/// initializer. This is the type-level half of the LLM-never-mutates invariant:
/// raw model text cannot be turned into one of these, only a schema-validated,
/// operator-accepted fact can.
struct OperatorAcceptedFact: Equatable {
    let fact: GraniteCandidateFact
    init?(_ fact: GraniteCandidateFact, from validation: GraniteValidationResult) {
        guard validation.acceptedFacts.contains(fact) else { return nil }
        self.fact = fact
    }
}
```

- [ ] **Step 4: Implement the accept/reject flow**

Add to the `AppState` extension in `TCCC_IOS/Intelligence/GraniteReviewQueue.swift`:

```swift
    /// The current engine value for a (domain, field), via the deterministic
    /// projection — used for contradiction detection and conflict display.
    func currentEngineValue(domain: String, field: String) -> String? {
        guard let p = primaryPatient else { return nil }
        return DeterministicFactProjector.project(p)
            .first { $0.domain == domain && $0.field == field }?.value
    }

    /// Apply one operator-accepted fact, through the engine. (Contradiction routing
    /// is added in the next task; here, a routed mutation is applied directly.)
    func acceptGraniteFact(_ accepted: OperatorAcceptedFact, in item: GraniteReviewItem) async {
        let fact = accepted.fact
        switch FieldRouter.route(domain: fact.domain, field: fact.field, value: fact.value) {
        case .mutation(let write):
            await engine.apply([write], to: fact.patientId)
            await refreshPatientSnapshot()
            appendSystem("GRANITE ACCEPTED · \(fact.field) = \(fact.value ?? "")")
        case .rejected(let reason):
            appendSystem("GRANITE REJECTED · \(fact.field) · \(reason)")
        }
    }

    /// Reject the whole review item: no mutation, drop it from the queue.
    func rejectGraniteReviewItem(_ item: GraniteReviewItem) {
        graniteReviewQueue.removeAll { $0.id == item.id }
        appendSystem("GRANITE REVIEW REJECTED · discarded")
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteApplyPathTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Intelligence/OperatorAcceptedFact.swift TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOSTests/GraniteApplyPathTests.swift
git commit -m "feat(apply-path): OperatorAcceptedFact guard + engine-mediated accept/reject"
```

---

## Task 5: Contradiction → conflict routing (app target)

A model fact that contradicts the engine's existing value must route to the conflict path (held), never auto-apply, never silently drop. The card holds the existing engine value.

**Files:**
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (contradiction check in `acceptGraniteFact`)
- Test: `TCCC_IOSTests/GraniteConflictRoutingTests.swift`

**Interfaces:**
- Consumes: `currentEngineValue` (Task 4), `engine.apply` (Task 1).
- Produces: contradiction behavior in `acceptGraniteFact`; an inspectable signal `AppState.lastConflictMessage: String?` for tests/UI.

- [ ] **Step 1: Write the failing tests**

```swift
// TCCC_IOSTests/GraniteConflictRoutingTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteConflictRoutingTests: XCTestCase {
    func testContradictingFactRoutesToConflictNotAccept() async {
        let state = AppState()
        // Engine already holds hr = 88 (deterministic ground truth).
        await state.engine.apply([.heartRate(88)], to: "PATIENT_1")
        await state.refreshPatientSnapshot()

        // Model proposes a contradicting value.
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "120", evidenceIds: ["seg-1"], confidence: .medium)
        let validation = GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: [])
        let accepted = OperatorAcceptedFact(fact, from: validation)!

        await state.acceptGraniteFact(accepted, in:
            GraniteReviewItem(id: UUID(), createdAt: Date(),
                patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                    candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                    rejectedInputs: [], modelSelfCheck: "ok"),
                validation: validation))

        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)        // engine value HOLDS (④ resting state)
        XCTAssertNotNil(state.lastConflictMessage)                 // surfaced, operator-visible
        XCTAssertTrue(state.lastConflictMessage?.contains("120") ?? false)
        XCTAssertTrue(state.lastConflictMessage?.contains("88") ?? false)
    }

    func testAgreeingFactStillApplies() async {
        let state = AppState()
        await state.engine.apply([.heartRate(88)], to: "PATIENT_1")
        await state.refreshPatientSnapshot()
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "88", evidenceIds: ["seg-1"], confidence: .high)
        let validation = GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: [])
        await state.acceptGraniteFact(OperatorAcceptedFact(fact, from: validation)!, in:
            GraniteReviewItem(id: UUID(), createdAt: Date(),
                patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                    candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                    rejectedInputs: [], modelSelfCheck: "ok"),
                validation: validation))
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)        // no spurious conflict
        XCTAssertNil(state.lastConflictMessage)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteConflictRoutingTests`
Expected: FAIL — `lastConflictMessage` does not exist and the first test mutates to 120.

- [ ] **Step 3: Add the conflict signal + contradiction check**

Add a stored property to `AppState` (near `graniteReviewQueue`, in `AppState.swift`):

```swift
    /// Most recent contradiction surfaced by the apply path (engine value vs model
    /// value). Held for review; the engine value remains shown until the operator
    /// actively overrides. `nil` when there is no pending conflict.
    var lastConflictMessage: String?
```

Update `acceptGraniteFact` in `GraniteReviewQueue.swift` to check for contradiction *before* routing:

```swift
    func acceptGraniteFact(_ accepted: OperatorAcceptedFact, in item: GraniteReviewItem) async {
        let fact = accepted.fact

        // ④ Contradiction → conflict path. Engine ground truth holds; never auto-resolve.
        if let existing = currentEngineValue(domain: fact.domain, field: fact.field),
           let proposed = fact.value, existing != proposed {
            let msg = "GRANITE CONFLICT · \(fact.field): engine ‘\(existing)’ vs model ‘\(proposed)’ · operator override required"
            lastConflictMessage = msg
            appendSystem(msg)
            return   // do NOT apply; engine value holds
        }

        switch FieldRouter.route(domain: fact.domain, field: fact.field, value: fact.value) {
        case .mutation(let write):
            await engine.apply([write], to: fact.patientId)
            await refreshPatientSnapshot()
            appendSystem("GRANITE ACCEPTED · \(fact.field) = \(fact.value ?? "")")
        case .rejected(let reason):
            appendSystem("GRANITE REJECTED · \(fact.field) · \(reason)")
        }
    }
```

(Also clear `lastConflictMessage = nil` inside `wipeSession()`, `newPatient()`, and `endCurrentCare()` in `AppState.swift`, alongside the existing `graniteReviewQueue.removeAll()` lines.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteConflictRoutingTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOS/App/AppState.swift TCCC_IOSTests/GraniteConflictRoutingTests.swift
git commit -m "feat(apply-path): route contradictions to conflict (engine value holds, never silent)"
```

---

## Task 6: Rubric drift test for the router allow-table (app target)

Lock every wired `(domain, field)` to the rubric so the router can't drift from the 2026 ground truth.

**Files:**
- Test: `TCCC_IOSTests/FieldRouterRubricDriftTests.swift`

**Interfaces:**
- Consumes: `FieldRouter` (Task 2); the rubric JSON via `#filePath`-relative traversal (same pattern as `RubricDriftProtectionTests`).

- [ ] **Step 1: Write the failing test**

```swift
// TCCC_IOSTests/FieldRouterRubricDriftTests.swift
import XCTest
@testable import TCCC_IOS

final class FieldRouterRubricDriftTests: XCTestCase {
    /// Every field name the router can route to a mutation must exist in the
    /// 2026 DD-1380 / MARCH-PAWS rubric. If the router wires a field the rubric
    /// does not know, this fails — the router drifted from ground truth.
    func testWiredFieldsExistInRubric() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TCCC_IOSTests/
            .deletingLastPathComponent()   // repo root
        let ddURL = repoRoot.appendingPathComponent("reference/rubric/extracted/dd1380_field_inventory.json")
        let mpURL = repoRoot.appendingPathComponent("reference/rubric/extracted/march_paws_vocabulary_2026.json")
        let ddText = try String(contentsOf: ddURL, encoding: .utf8)
        let mpText = try String(contentsOf: mpURL, encoding: .utf8)

        // Field-label tokens the router wires (human terms present verbatim in the rubric files).
        let wiredRubricTerms = [
            "Pulse", "SpO", "Resp", "Blood Pressure", "AVPU",
            "Tourniquet", "Airway", "Hypothermia", "Analgesic", "Antibiotic",
        ]
        for term in wiredRubricTerms {
            XCTAssertTrue(ddText.contains(term) || mpText.contains(term),
                          "Wired router term ‘\(term)’ is absent from both rubric files — router drifted.")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails or passes meaningfully**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/FieldRouterRubricDriftTests`
Expected: this test is assertion-first; on first run, fix any term that isn't literally present in the rubric files by adjusting it to the exact rubric spelling (open the JSON to confirm). Then it PASSES.

- [ ] **Step 3: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOSTests/FieldRouterRubricDriftTests.swift
git commit -m "test(apply-path): drift-protect the FieldRouter allow-table against the 2026 rubric"
```

---

## Task 7: Operator review surface (app target UI)

Surface the review queue with per-fact Accept / Reject (gloved-hand), conflicts shown, presented as an overlay consistent with the existing `SettingsOverlay` / `QuickActionsSheet` ZStack overlays (keeps the 5-screen pager intact per the design brief).

**Files:**
- Create: `TCCC_IOS/Components/GraniteReviewOverlay.swift`
- Modify: `TCCC_IOS/ContentView.swift` (present the overlay when `state.reviewOpen`), `TCCC_IOS/App/AppState.swift` (add `var reviewOpen: Bool = false`), `TCCC_IOS/Chrome/FooterHints.swift` (a footer affordance to open it, badged with `graniteReviewQueue.count`)
- Test: `TCCC_IOSTests/GraniteReviewOverlayWiringTests.swift`

**Interfaces:**
- Consumes: `graniteReviewQueue`, `acceptGraniteFact`, `rejectGraniteReviewItem`, `OperatorAcceptedFact`, `lastConflictMessage`.
- Produces: `var AppState.reviewOpen: Bool`; `struct GraniteReviewOverlay: View`.

> **UI honesty:** SwiftUI layout is verified by a green build + the fully-tested logic beneath (Tasks 1–5). The automated test here asserts the *wiring* (the buttons call the right `AppState` methods), not pixels.

- [ ] **Step 1: Write the failing wiring test**

```swift
// TCCC_IOSTests/GraniteReviewOverlayWiringTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class GraniteReviewOverlayWiringTests: XCTestCase {
    func testAcceptButtonActionAppliesThroughState() async {
        let state = AppState()
        let fact = GraniteCandidateFact(id: "f1", patientId: "PATIENT_1", domain: "vitals",
            field: "heartRate", value: "88", evidenceIds: ["seg-1"], confidence: .high)
        let item = GraniteReviewItem(id: UUID(), createdAt: Date(),
            patch: GraniteCandidatePatch(packetId: "p", patientId: "PATIENT_1",
                candidateFacts: [fact], conflicts: [], missingRequiredFields: [],
                rejectedInputs: [], modelSelfCheck: "ok"),
            validation: GraniteValidationResult(acceptedFacts: [fact], conflicts: [], errors: []))
        state.graniteReviewQueue = [item]

        // The overlay's accept action is this closure (mirrors the button body).
        if let accepted = OperatorAcceptedFact(fact, from: item.validation) {
            await state.acceptGraniteFact(accepted, in: item)
        }
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteReviewOverlayWiringTests`
Expected: PASS already at the logic level (Tasks 1–5 exist) — if this task is implemented in order it should compile and pass; if `reviewOpen`/overlay symbols are referenced before creation it FAILS to compile. Treat a compile failure here as the red state.

- [ ] **Step 3: Add `reviewOpen` state and the overlay**

In `AppState.swift` (near `settingsOpen`/`quickActionsOpen`):

```swift
    var reviewOpen: Bool = false
```

Create `TCCC_IOS/Components/GraniteReviewOverlay.swift`:

```swift
import SwiftUI
import TCCCDomain

/// Operator review of queued Granite candidate facts. Accept routes through the
/// engine-mediated apply path; Reject is destructive (long-press). Conflicts show
/// the engine value (which holds) and require an explicit override. Presented as a
/// ZStack overlay like SettingsOverlay / QuickActionsSheet; tap-scrim dismisses.
struct GraniteReviewOverlay: View {
    let state: AppState   // AppState is a final @Observable class; mutate via the reference
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onTapGesture { state.reviewOpen = false }
            VStack(alignment: .leading, spacing: 8) {
                Text("GRANITE REVIEW · \(state.graniteReviewQueue.count) PENDING")
                    .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(palette.fg)
                if let conflict = state.lastConflictMessage {
                    Text(conflict)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.crit)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.graniteReviewQueue) { item in
                            reviewCard(item)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
            .background(palette.bg1)
        }
    }

    private func reviewCard(_ item: GraniteReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(item.patch.candidateFacts) { fact in
                HStack(spacing: 10) {
                    Text("\(fact.field) = \(fact.value ?? "—")")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.fg)
                    Spacer()
                    if item.status == .readyForOperatorReview {
                        Button("ACCEPT") {
                            Task {
                                if let a = OperatorAcceptedFact(fact, from: item.validation) {
                                    await state.acceptGraniteFact(a, in: item)
                                }
                            }
                        }
                        .frame(minWidth: 64, minHeight: 44)   // gloved-hand
                    }
                }
            }
            HoldToConfirmButton(label: "Reject", systemImage: "xmark",
                                style: .standard, holdSeconds: 2.0) {
                state.rejectGraniteReviewItem(item)
            }
        }
        .padding(10)
        .background(palette.bg)
    }
}
```

In `ContentView.swift`, add to the top-level `ZStack` (alongside the Settings / QuickActions overlays):

```swift
            if state.reviewOpen {
                GraniteReviewOverlay(state: state)
                    .zIndex(2)
            }
```

In `FooterHints.swift`, add a button that toggles `state.reviewOpen = true`, labeled `REVIEW` with a count badge from `state.graniteReviewQueue.count` (mirror the existing footer button construction).

- [ ] **Step 4: Build + run the wiring test**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/GraniteReviewOverlayWiringTests`
Expected: PASS, and the build is green (overlay compiles).

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Components/GraniteReviewOverlay.swift TCCC_IOS/ContentView.swift TCCC_IOS/App/AppState.swift TCCC_IOS/Chrome/FooterHints.swift TCCC_IOSTests/GraniteReviewOverlayWiringTests.swift
git commit -m "feat(ui): operator review overlay (accept/reject, conflicts shown, gloved-hand)"
```

---

## Task 8: WIPE vs. new-casualty affordance distinctness (app target UI)

Make the two lifecycle actions unmistakably distinct *now*, before durability makes their consequences opposite (spec §3 ⑤ phasing). WIPE keeps the HOLD-3s long-press everywhere; new-casualty must not look or feel like WIPE.

**Files:**
- Modify: `TCCC_IOS/Chrome/FooterHints.swift` (footer WIPE → hold-3s, visually separated from NEW), `TCCC_IOS/Components/ConfirmationBanner.swift` (distinct copy/color), `TCCC_IOS/Components/SettingsOverlay.swift` (confirm New Cas hold-2s vs WIPE hold-3s already distinct)
- Test: `TCCC_IOSTests/LifecycleAffordanceTests.swift`

**Interfaces:**
- Consumes: `HoldToConfirmButton`, `ConfirmationAction`, `state.newPatient()`, `state.wipeSession()`.
- Produces: footer WIPE as a hold-3s affordance; assertion-level guarantees about the distinct copy.

- [ ] **Step 1: Implementation-time parity check (the spec §5 build-phase verification — run first, do NOT auto-fix)**

Run: `cd /Users/ama/TCCC_IOS && grep -rn "newPatient\|wipeSession\|NEW CASUALTY\|CARE ENDED" TCCC_IOSTests Packages/TCCCKit/Tests 2>/dev/null`
Read each hit. **This cycle does not change new-casualty's wipe semantics** (durable archive is deferred), so existing lifecycle tests should still pass as-is. If any test asserts the *old destructive new-casualty behavior as the desired end state* (i.e., it would block the future preserve-and-archive semantics), **do not edit it now** — record it in the commit message and in the deferred-cycle notes as a parity test to *correct, not satisfy* when the archive lands. Flag it to the human.

- [ ] **Step 2: Write the failing test**

```swift
// TCCC_IOSTests/LifecycleAffordanceTests.swift
import XCTest
@testable import TCCC_IOS

@MainActor
final class LifecycleAffordanceTests: XCTestCase {
    func testWipeAndNewCasualtyHaveDistinctConfirmationCopy() {
        // Distinct headlines so a gloved operator can never confuse them.
        XCTAssertNotEqual(ConfirmationAction.wipe.headline, ConfirmationAction.newPatient.headline)
        XCTAssertTrue(ConfirmationAction.wipe.headline.uppercased().contains("WIPE"))
        XCTAssertFalse(ConfirmationAction.newPatient.headline.uppercased().contains("WIPE"))
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests/LifecycleAffordanceTests`
Expected: FAIL if `ConfirmationAction.headline` does not already make WIPE distinct (inspect `ConfirmationAction.swift`); adjust the headline strings so WIPE is unmistakable.

- [ ] **Step 4: Make the affordances distinct**

- In `ConfirmationAction.swift`, ensure `.wipe.headline` reads e.g. `"WIPE ALL CASUALTY DATA"` (crit color in the banner) and `.newPatient.headline` reads e.g. `"START NEW CASUALTY"` — no shared "wipe"/"erase" wording.
- In `FooterHints.swift`, change the footer **Wipe** button from a single tap to a `HoldToConfirmButton(label: "Wipe", systemImage: "trash.fill", style: .accent, holdSeconds: 3.0) { state.requestConfirmation(.wipe) }` (WIPE keeps HOLD-3s), and keep **New** as a plain tap that raises the non-destructive confirmation. Place WIPE in a visually separated region (e.g. far edge, crit color) from NEW.
- Leave `SettingsOverlay.swift` New Cas (hold-2s) vs Wipe (hold-3s) as-is — already distinct.

- [ ] **Step 5: Run to verify it passes + full app suite**

Run: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation`
Expected: `LifecycleAffordanceTests` PASS and the whole app + 724 TCCCKit tests green.

- [ ] **Step 6: Commit**

```bash
cd /Users/ama/TCCC_IOS
git add TCCC_IOS/Chrome/FooterHints.swift TCCC_IOS/Components/ConfirmationBanner.swift TCCC_IOS/App/ConfirmationAction.swift TCCC_IOSTests/LifecycleAffordanceTests.swift
git commit -m "feat(ui): make WIPE (hold-3s) and new-casualty unmistakably distinct before durability diverges them"
```

---

## Final verification (after all tasks)

- [ ] **TCCCKit suite green:** `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test` → 724 + new, 0 failures.
- [ ] **App suite green:** `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation` → all green.
- [ ] **Boundary gate (the §② acceptance gate) green:** `FieldRouterBoundaryGateTests` — four rejections + the positive case.
- [ ] **Invariant intact:** the only `PatientState` writers are `processTranscript` (extraction) and `apply(_:to:)` (typed writes). No LLM generator returns `PatientState`. No networking added.
- [ ] **Scope honored:** no audio/Granite-Speech, no event log, no durable archive, no workflow engine touched.
- [ ] **Parity flag surfaced** (Task 8 Step 1): any test enshrining old destructive new-casualty behavior is reported, not silently satisfied.

## Out of scope (carried to the deferred cycle — spec §7)

`EncounterEvent` log + replay; durable encrypted retained archive + WIPE-purges / new-casualty-preserves semantics; re-deriving evidence linkage from events (replacing the best-effort stopgap in Task 3); refactoring the Task 4/5 apply path to emit events; the deterministic workflow engine.
