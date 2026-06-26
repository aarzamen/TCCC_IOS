# Engine Incremental Projection (BLOCK A) — Design Spec

**Date:** 2026-06-25
**Branch:** `engine-incremental-projection` (off `main` @ `4e9d570`)
**Source:** the `granite-asr-efficiency-recon` investigation (ranks 1 + 2) — the two high-impact, in-lane inefficiencies the event-sourcing A+B cycle knowingly deferred ("incremental replay is a deferred optimization").
**Operator-confirmed symptom:** the app gets heavier/laggier as an encounter grows during capture.

---

## 1. Goal

Stop recomputing the entire projection on every engine mutation. Today `PatientState` is re-folded from the whole event log on each transcript line and each operator accept (O(N) per call → O(N²) per encounter), and the persistence hot-path deep-copies the whole `EncounterLog` on every flush. Make both **incremental** — with **zero observable behavior change**: the log stays canonical, and `snapshot() == project(log)` still holds (now as an *asserted invariant*, the de-risker).

## 2. The inefficiencies (evidence)

| # | Cost | Site | Fires |
|---|------|------|-------|
| 1 | Full-log re-fold | `PatientStateEngine.swift:128` `patients = Self.project(log)`; `:172` same in `recordOperatorAcceptedFact` | ~100–150×/encounter (per transcript line) + per accept |
| 2 | Whole-`EncounterLog` value copy | `AppState.swift:556` `persistNewEvents()` → `engine.snapshotLog()` deep-copies the struct | ~150–200×/encounter (every `refreshPatientSnapshot`) |

## 3. The change

### Rank 1 — incremental projection (TCCCKit, `PatientStateEngine`)
The imperative extractor loop in `processTranscript` **already** maintains `patients` (line 124 `patients[currentPatientID] = current`). Line 128 then overwrites it with `project(log)` — a re-fold that, by the A2 inverse property (`apply(diff(b,a)) == a`) and the A3 equivalence test, is *provably equal* to the imperative result. So:

- **`processTranscript`:** delete line 128. `patients` remains the imperatively-maintained materialized view; `snapshot()` returns it.
- **`recordOperatorAcceptedFact`:** replace line 172 `patients = Self.project(log)` with an in-place apply of the just-recorded write (matching exactly what `project` does for an `operatorAcceptedFact` event):
  ```swift
  var p = patients[patientId]!            // ensurePatientExists already ran
  Self.applyWrite(write, to: &p)
  p.timestampLastUpdate = unix            // == the event's timestampUnix, as project sets it
  patients[patientId] = p
  ```

`project(log)` (the pure full re-fold) is **unchanged** and stays the authority for `restore(_:)` (replay-on-launch) and as the equivalence oracle. The materialized `patients` is now a cache that is **provably never divergent** from `project(log)` — by induction over calls (each call's emitted deltas equal `diff(before, after)`, and replaying all deltas reconstructs the accumulated imperative result).

### Rank 2 — slice accessor for persistence (TCCCKit + app)
Add a small accessor that returns only the events past a cursor instead of copying the whole log:
```swift
/// Events appended since `index` (a small slice copy) — for incremental
/// persistence without deep-copying the entire EncounterLog struct.
public func newEvents(since index: Int) -> [EncounterEvent] {
    guard index < log.events.count else { return [] }
    return Array(log.events[index...])
}
```
`AppState.persistNewEvents()` uses it:
```swift
let new = await engine.newEvents(since: persistedCursor)
guard !new.isEmpty else { return }
try await store.appendToActive(new)
persistedCursor += new.count
```
`snapshotLog()` stays (its full-log consumers — `deterministicFactsForPacket`, `restore`, the equivalence tests — genuinely need the whole log; those are BLOCK B / out of scope here).

## 4. Invariants preserved

- **The log stays canonical.** `project(log)` on `restore` reconstructs state on launch (unchanged). The live `patients` is a materialized view of that fold.
- **`snapshot() == project(log)` becomes an asserted invariant** — the materialized view must never diverge from the full re-fold. This is the de-risker (§6).
- **LLM-never-mutates-state** is untouched — operator facts still reach state only via `OperatorAcceptedFact` → `FieldRouter` → `PatientStateFieldWrite` → `applyWrite`; the accept path just applies the write directly instead of re-folding to apply it.
- **Persistence semantics unchanged** — `persistNewEvents` still flushes exactly the new events, cursor-guarded; only the copy shrinks from whole-log to slice.

## 5. Module placement

All in TCCCKit / `TCCCExtractor` (the engine) + one app-layer call-site edit (`AppState.persistNewEvents`). No new types, no public-API breakage (`snapshot()`/`snapshotLog()`/`project` signatures unchanged; `newEvents(since:)` is additive).

## 6. The de-risker (why this is low-risk)

The **existing** `LogEquivalenceTests` already assert `project(engine.snapshotLog()) == engine.snapshot()` over the four scenario fixtures + the multi-chunk case (`testAfterFlipSnapshotIsTheProjection`, the per-scenario equivalence tests). After this change, `snapshot()` is the incremental materialized view, so those tests **directly verify incremental == full-re-fold** — they were written for the A5 flip and now gate the optimization for free. We add:
- A **divergence stress test**: a long sequence of `processTranscript` calls *interleaved with operator accepts*, then assert `snapshot() == project(snapshotLog())` (the operator-accept-then-reproject path isn't covered by the transcript-only fixtures — this closes that gap).
- A **slice-accessor test**: `newEvents(since:)` returns the correct suffix and `[]` when caught up.

## 7. Acceptance gate

1. **All 755 TCCCKit + 84 app tests green** — the existing equivalence tests passing *is* the proof that `snapshot()` still equals `project(log)`.
2. New divergence stress test green (incremental never diverges across transcript + accept sequences).
3. `newEvents(since:)` slice test green; `persistNewEvents` persistence tests (B4/B5) stay green.
4. Whole-branch opus review re-verifies the materialized-view-never-diverges invariant and that `project(log)` is still the restore authority.

## 8. Out of scope

- **BLOCK B** (hotseat-LLM micro-opts — `deterministicFactsForPacket` incremental scan, per-field projection caching, validator dedup) — a separate, smaller block.
- **Rank 7** (`emitEvents` diffing all patients) — deferred. Note: the investigation's "only diff `currentPatientID`" sketch is **unsafe** for multi-patient calls (a patient switch changes more than one patient within a single call); a correct version tracks *touched* patients. Low impact (empty diffs are cheap), not worth the complexity now.
- The **audio lane** (Granite Speech ASR, `AudioFrameLedger`, chunked-encode) — Codex's (`SPRINT_BOARD.yaml: sprint_2_in_progress`). Untouched.
