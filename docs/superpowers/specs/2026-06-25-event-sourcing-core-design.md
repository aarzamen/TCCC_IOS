# Event-Sourcing Core (Sub-cycle A) — Design Spec

**Date:** 2026-06-25
**Branch:** `event-sourcing-core` (off `main` @ `89de5e8`)
**Predecessor:** reconciliation apply path, shipped @ `89de5e8`.
**North star:** `docs/superpowers/specs/2026-06-24-reconciliation-apply-path-design.md` §7.
**Roadmap:** `docs/superpowers/2026-06-24-next-cycle-event-sourcing-kickoff.md`.
**Grounding:** read-only 8-agent current-code map, 2026-06-25 (run `wf_306e9bb3-78a`).

---

## 1. Goal

Make an immutable `EncounterEvent` log the canonical memory of an encounter, with
`PatientState` a deterministic **projection (fold)** of that log instead of an
independently-mutated value. This sub-cycle delivers the event spine **in memory**
— no persistence. Persistence, the retained archive, replay-on-launch, and the
PRESERVE/PURGE lifecycle are **sub-cycle B** (previewed in §9, not built here).

**Operator decision (2026-06-25):** the permanent casualty record is a **fat log** —
every deterministic machine inference is stored as its own discrete, evidence-linked
event, not merely re-derived. This is a medico-legal fidelity choice: the record must
show *what the device inferred, from which spoken words, at care-time*.

## 2. Locked decisions

| # | Decision | Rationale |
|---|----------|-----------|
| F0 | **Two sub-cycles, A then B.** This spec = A. | The A5 canonical flip is the single highest-risk change; isolate it from disk I/O. |
| F1 | **Fat event log** (operator's choice). Cases: `asrSegment`, `deterministicFact`, `operatorAcceptedFact`, `operatorRejectedFact`, `lifecycle`. | Maximal medico-legal audit trail; every inference stored with evidence. |
| F2 | **`EncounterEvent` lives in TCCCKit / `TCCCDomain`**, payloads are TCCCKit-native value types; evidence is `[String]` segment-IDs, not embedded app structs. | Preserves the unidirectional app→TCCCKit dependency; keeps the log lean and `Codable`. |
| F3 | **Fold replays the recorded deltas** (`deterministicFact` + `operatorAccepted` events) from a fresh base; it does **not** re-run extractors. Extraction runs once, at command time. | Re-running extractors in the fold is **non-deterministic** — `Intervention` mints a fresh `UUID()` per creation — so it would break full-`==` equivalence and churn SwiftUI list identity every transcript line. Replaying captured deltas (which carry each `Intervention`'s original UUID/timestamp) is deterministic: `project(log) == capturedState` exactly. The log is canonical from sub-cycle A; B adds only persistence + replay-on-launch. |
| F4 | **Dual-write → equivalence-gated flip** (not big-bang). | A4 builds the log as a zero-risk shadow; A5 flips canonical with the A3 equivalence test as the gate. |
| F9 | **Evidence linkage via per-`asrSegment` state diff**, computed in the command path. | Real `evidenceIds` with **zero extractor edits** and **no `ExtractionContext` change** — replaces the `evidenceIds: []` stopgap. |
| F10 | **LLM-never-mutates-state stays structural.** | Operator-origin facts still flow `OperatorAcceptedFact` → `FieldRouter` → `PatientStateFieldWrite` → engine; the event only wraps that path. No new mutation entry point. |

## 3. The fat-log insight (why "fat" is cheap here)

A naïve fat log makes extractors *emit* fact events — changing the `ExtractorPass`
signature and touching all 11 extractors plus their tests. We avoid that entirely:

> The fact events are produced by **diffing `PatientState` before and after each
> `asrSegment` is processed.** Whatever fields changed → one `deterministicFact`
> event per changed field, `evidenceIds = [thatSegmentId]`. The extractors are
> never touched.

This same diff is the evidence-linkage mechanism (F9). One new function carries
both responsibilities:

```
func diff(_ before: PatientState, _ after: PatientState) -> [PatientStateDelta]
```

`PatientStateDelta` is a typed enum spanning **every writable field** of
`PatientState` (see §5). It is the audit-grain vocabulary; the existing
`PatientStateFieldWrite` (the 11-case operator-write enum) is unchanged and is a
*subset* expressible as deltas — they converge later, not in A.

## 4. Architecture (CQRS-shaped)

```
                    ┌──────────────────────── COMMAND (write) ───────────────────────┐
  ASR / operator →  │ processTranscript(text)   acceptGraniteFact / reject           │
                    │   run 11 extractors          OperatorAcceptedFact guard         │
                    │   diff(before, after)        → FieldRouter → PatientStateFieldWrite│
                    │        │                          │                              │
                    │        ▼ append                   ▼ append                       │
                    └───────── EncounterLog (append-only, [EncounterEvent]) ──────────┘
                                          │
                                          ▼ fold (projection / read)
                    project(log) → [String: PatientState]      ← snapshot() returns this
```

- **Command side** runs business logic (extractors, validation, routing) and emits
  events. This is the *only* place extraction happens.
- **Projection side** (`project`) folds the log into `PatientState` by **replaying the
  recorded deltas** in order — `deterministicFact` events apply their `PatientStateDelta`,
  `operatorAcceptedFact` events apply their `PatientStateFieldWrite`. It does **not**
  re-run extractors (see F3). `asrSegment` events are raw evidence; `operatorRejectedFact`
  and `lifecycle` events do not affect projected state.
- `PatientState` is **never independently mutated** after the flip; it is always
  `project(log)`. `project` is a pure function; the engine remains the sole writer of
  its stored `patients` (it assigns `patients = project(log)`).

### 4.1 Reducer fold model (F3)

`snapshot()` returns `project(log)`. After the A5 flip, `processTranscript` does:

```
let before = projectedState               // = project(log) so far
runExtractorsImperatively(text)           // existing extractor code path, UNCHANGED — runs ONCE
let after = resultingState
let deltas = diff(before, after)          // captures EXACT outputs, incl. each Intervention's UUID
log.append(.asrSegment(text, id: segId, …))
for d in deltas { log.append(.deterministicFact(delta: d, evidenceIds: [segId], …)) }
patients = project(log)                    // ← THE FLIP: replay ALL deltas from a fresh base
```

`project(log)` starts from a fresh default state and **applies every recorded delta in
order** (plus operator-accepted writes) — it never re-runs extractors. Because each
call's deltas are `diff(before, after)` and `apply(diff(b,a)) == a` (the inverse
property, A2), the chained replay reconstructs `after` exactly — *including* the
non-deterministic identities (UUIDs/timestamps) that re-running extractors would
regenerate differently. The **A3 equivalence test** proves `project(log) == imperative
result` via full `==` on the `[String: PatientState]` dict, over the four real
`EndToEndScenario` fixtures, before A5 lands.

Replay cost is O(total deltas) per snapshot; sub-millisecond for a casualty's
few-hundred deltas. No mutable cache exists to diverge. Incremental replay is a
deferred optimization — not in A.

### 4.2 Evidence boundary (F9)

One `asrSegment` event per `processTranscript` call (the app's committed-line unit
via `appendFinal`), carrying a stable id (`seg-<n>`). All `deterministicFact` events
from that call carry `evidenceIds = [thatSegmentId]`. Sentence-level evidence (finer
than line-level) is a future refinement, explicitly out of scope for A.

## 5. Types (TCCCKit / `TCCCDomain`)

All `Codable, Sendable, Equatable`. Payloads carry `id`, `patientId`, `timestampUnix`.

```swift
public enum EncounterEvent: Codable, Sendable, Equatable, Identifiable {
    case asrSegment(ASRSegmentPayload)
    case deterministicFact(DeterministicFactPayload)
    case operatorAcceptedFact(OperatorDecisionPayload)
    case operatorRejectedFact(OperatorDecisionPayload)
    case lifecycle(LifecyclePayload)
    public var id: String { /* payload.id */ }
}

public struct ASRSegmentPayload: Codable, Sendable, Equatable {
    public let id: String                 // "seg-<n>"
    public let patientId: String
    public let timestampUnix: Double
    public let text: String               // committed transcript text
    public let backend: String            // ASR backend label (string, not the app enum)
    public let isFinal: Bool
}

public struct DeterministicFactPayload: Codable, Sendable, Equatable {
    public let id: String                 // "fact-<n>"
    public let patientId: String
    public let timestampUnix: Double
    public let delta: PatientStateDelta    // the typed field change
    public let evidenceIds: [String]       // [asrSegment.id] that produced it
    public let extractor: String           // best-effort attribution label
}

public struct OperatorDecisionPayload: Codable, Sendable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public let write: PatientStateFieldWrite?  // accepted+routable: the applied write; rejected/unroutable: nil
    public let sourceFactId: String?           // the candidate fact id (audit link)
    public let domain: String                  // always recorded (audit of what was proposed)
    public let field: String
    public let rawValue: String?
}

public struct LifecyclePayload: Codable, Sendable, Equatable {
    public let id: String
    public let patientId: String
    public let timestampUnix: Double
    public enum Kind: String, Codable, Sendable { case encounterStarted, encounterEnded, archived }
    public let kind: Kind
}
```

### 5.1 `PatientStateDelta` (the audit-grain vocabulary)

A typed enum covering **every writable field** of `PatientState` and its nested
structs. The plan enumerates the full case list by walking the verbatim field
inventory below; the diff function maps `(before, after)` to a list of these.

- **`PatientState`** (`PatientState.swift`): `mechanismOfInjury: String?`,
  `interventions: [Intervention]` (append), `injuries: [String]` (append),
  `marchPhase: MarchPhase`, `classification: Classification?`,
  `timestampFirstMention`/`timestampLastUpdate: Double?`.
- **`MARCHState`** (`MARCHState.swift`): `hemorrhageIdentified/Assessed: Bool`,
  `hemorrhageLocation/Intervention: String?`, `hemorrhageEffective: Bool?`,
  `airwayStatus/Intervention: String?`, `respirationStatus/Intervention/breathSounds`,
  `pulseStatus/skinSigns/circulationIntervention`, `consciousness/pupilResponse/hypothermiaPrevention`.
- **`Vitals`**, **`PAWSAssessment`**: every `var` (plan enumerates from source).

> **Faithfulness requirement:** `diff` must be **total** — `apply(diff(before, after)) ==
> after` for *any* before/after pair the extractors can produce (scalar sets,
> optional-nils, collection mutations). Scalars and optionals emit a set-delta on change.
> Collections (`injuries`, `interventions`) emit per-element **append** deltas when
> `after` extends `before` as a prefix (the normal case — preserves per-inference audit
> grain and each `Intervention`'s UUID); otherwise they emit a whole-array **set**
> delta as a totality fallback. This is the central correctness obligation of the diff
> function, tested directly (§7, A2-unit, every delta case) in addition to the
> end-to-end equivalence test (A3).

### 5.2 `EncounterLog`

```swift
public struct EncounterLog: Sendable, Equatable, Codable {
    public private(set) var events: [EncounterEvent] = []
    public mutating func append(_ event: EncounterEvent)
}
```

Mirrors the shape of the existing `TranscriptSegmentLedger` (private storage +
`mutating append`). One log per casualty.

## 6. Reuse inventory — do NOT rebuild

| Reused as-is | Module |
|---|---|
| 11 extractors + `ExtractorPass` (pure, stateless) | TCCCKit/`TCCCExtractor` |
| `ExtractionContext` (**no new field needed**) | TCCCKit |
| `SentenceTokenizer`, `SpokenNumberNormalizer`, `NegationDetector`, `PatientSwitcher` | TCCCKit |
| `PatientState`, `MARCHState`, `Vitals`, `PAWSAssessment` (already `Codable`/`Sendable`) | TCCCKit |
| `PatientStateFieldWrite` + `engine.apply(_:to:)` | TCCCKit |
| `OperatorAcceptedFact` guard, `FieldRouter`, `GraniteSchemaValidator` | app/`Intelligence` |
| `TranscriptSegmentLedger` (shape template for `EncounterLog`) | app/`Audio` |
| `ProtectedWrite` (extended in **B**, not A) | app/`App` |

## 7. Task outline (writing-plans expands to TDD steps)

Sub-cycle A only. A3's equivalence test **gates** the A5 flip.

- **A1.** `EncounterEvent` + payloads + `EncounterLog` in `TCCCDomain`. Tests: append,
  immutability, `Codable` round-trip for every case.
- **A2.** `PatientStateDelta` enum + `diff(before, after) -> [PatientStateDelta]`.
  Tests: per-field diff correctness **and the inverse property** `apply(diff(b,a)) == a`
  over hand-built states covering each field family.
- **A3.** `project(log) -> [String: PatientState]` (pure fold: start from a fresh
  default state, **apply every `deterministicFact` delta + `operatorAccepted` write in
  order**, ensuring patient rows exist by `patientId`; never re-run extractors).
  **Equivalence test** — build a log by processing each of the four
  `tests/scenarios/*.txt` fixtures exactly as `EndToEndScenarioTests` feeds them (one
  `processTranscript(wholeText)` call, fixed timestamp), capturing deltas, then assert
  `project(log)` equals the imperative `processTranscript` snapshot via **full `==`** on
  the `[String: PatientState]` dict (the de-risker). Idempotence asserted:
  `project(log) == project(log)`.
- **A4.** Dual-write (additive, zero-risk): `processTranscript` and the accept/reject
  handlers (`acceptGraniteFact` → `operatorAcceptedFact`, `rejectGraniteReviewItem` →
  `operatorRejectedFact`) **also** append events to a live `EncounterLog`; engine
  derivation unchanged; all 726 TCCCKit + 67 app tests stay green. Log built, not yet
  canonical.
- **A5.** **Flip:** `patients = project(log)`; `snapshot()` returns the fold. A3 gates.
  726 tests stay green. Verify **none** assert old direct-mutation internals.
- **A6.** Surface evidence: the review packet / extracted-fact UI reads `evidenceIds`
  from `deterministicFact` events; remove the `DeterministicFactProjector`
  `evidenceIds: []` stopgap. Test the linkage end-to-end.
- **A7.** Apply-path retrofit confirmation + **invariant test**: assert exactly one
  `engine.apply` site, fed only by `FieldRouter .mutation` via an
  `operatorAcceptedFact` event; LLM-never-mutates remains structural.
- **A8.** Polish carried from last cycle: enum-sync regression test
  (`FieldRouter` ↔ `PatientStateFieldWrite` ↔ `PatientStateDelta` coverage),
  `lifecycle` event emission (`encounterStarted`/`encounterEnded`), log-string
  consistency.

## 8. Acceptance gate (sub-cycle A)

1. **726 TCCCKit + 67 app tests green** at every task boundary (not just the end).
2. **A3 equivalence** holds field-by-field on all four scenario fixtures before A5.
3. **Diff inverse** (`apply(diff(b,a)) == a`) holds for every field family.
4. **Invariant**: one `engine.apply` site; no LLM consumer mutates state; operator
   facts reach state only through the validated event path.
5. **Evidence**: no `evidenceIds: []` stopgap remains; facts trace to a real segment id.
6. Whole-branch opus review re-verifies (2) and (4) survive the retrofit.

## 9. Sub-cycle B preview (DEFERRED — not built in this spec)

Named here so A's seams fit B; B gets its own brainstorming + spec.

- **Persistence:** append-only JSONL per casualty at
  `Documents/encounters/<casualtyId>/events.jsonl`. **`ProtectedWrite` has no append
  API today** (grounding) — B adds `appendLine(_:to:)` (FileHandle append +
  `markProtected` re-assert), tested for `NSFileProtectionComplete` persistence and
  **corrupt-tail recovery** (truncate mid-JSON → replay tolerates, recovers last-good).
- **Replay-on-launch:** the projection is **already canonical** (A replays deltas), so
  launch replay is the *same* `project(log)` over events read from disk — no new
  derivation path. The record is inherently frozen (immune to later extractor-logic
  change) because state flows from the stored deltas, not from re-run extractors. B adds
  the disk read + corrupt-tail tolerance only.
- **Archive + manifest:** `Documents/encounters/manifest.json` indexes casualties;
  scan-on-launch, cache in `AppState`, invalidate on `newPatient`/`wipeSession`.
  `schemaVersion` field for forward-compat (skip/no-op unknown event cases).
- **Lifecycle (F8):** `newPatient`/`endCurrentCare` **PRESERVE** (finalize + archive
  the active log, start a fresh one); `wipeSession` (WIPE HOLD-3s, affordance already
  built) **PURGES** the entire `encounters/` tree — with a post-delete `!exists`
  assertion so a silent failure can't show "WIPE complete." Parity flag from last
  cycle was clean: no test enshrines the old destructive new-casualty behavior.

## 10. Risks & mitigations (from grounding)

| Risk | Mitigation |
|---|---|
| **A5 flip silently regresses behavior** | A3 equivalence test on the 4 *real* fixtures, field-by-field, written and green **before** A5. |
| **`diff` misses a field family → wrong projected state** | A2 inverse-property test over **every** delta case (hand-built before/after); A3 full-`==` over fixtures. A missed field fails both. |
| **Re-running extractors in fold is non-deterministic (UUIDs/timestamps)** | Fold replays captured deltas (carrying original identities) instead; extraction runs once at command time. The flip never regenerates identities. |
| **Fold perf on long logs** | Sub-ms for hundreds of deltas; perf is not a constraint (iPhone 17 Pro). Incremental replay is a deferred optimization, not A. |
| **Scope creep — persistence/lifecycle bleeding into A** | Hard fence: A is in-memory only; all disk/lifecycle is B (§9). |
| **Schema evolution breaks old logs** | `schemaVersion` + unknown-case tolerance — a **B** concern (no persisted logs exist in A). |
| **Invariant erosion during retrofit** | A7 invariant test + whole-branch opus review (gate item 4/6). |

## 11. Out of scope (A)

Persistence, archive, manifest, replay-on-launch, lifecycle PRESERVE/PURGE (all B);
the workflow engine (C, deferred); the audio lane (Codex —
`AudioFrameLedger`/chunked-encode); multi-casualty UI; sentence-level evidence;
unifying `PatientStateFieldWrite` into `PatientStateDelta`.
