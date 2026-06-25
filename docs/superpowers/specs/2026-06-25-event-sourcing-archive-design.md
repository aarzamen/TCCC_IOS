# Event-Sourcing Durable Archive (Sub-cycle B) — Design Spec

**Date:** 2026-06-25
**Branch:** `event-sourcing-core` (continues from sub-cycle A; the whole event-sourcing feature merges when B is done)
**Predecessor:** sub-cycle A (in-memory event-sourcing core) @ `a390e6d` on this branch.
**Source:** the deferred scope in `2026-06-25-event-sourcing-core-design.md` §9 + the whole-branch review's Important #1.
**Grounding:** read-only 5-agent current-code map, 2026-06-25 (run `wf_3e065599-999`).

---

## 1. Goal

Persist the per-casualty `EncounterEvent` log to disk, **encrypted at rest** (`NSFileProtectionComplete`), **continuously** (after every committed event), so an in-progress encounter survives a crash and is **replayed on launch**. Retain past casualties as an on-disk archive indexed by a manifest. Wire the lifecycle: **New Casualty / End Care PRESERVE** (archive, never destroy); **WIPE (hold-3s) PURGES** the entire archive.

Sub-cycle A made `PatientState = project(log)` in memory. B makes that log durable.

## 2. Locked decisions

| # | Decision | Rationale |
|---|----------|-----------|
| B-persist | **Persist continuously** — new events flush to disk after every committed transcript line / accepted fact (operator decision, 2026-06-25). | A mid-care crash must lose at most the last partial line, not the casualty. Batch-on-handoff would defeat the §9 crash-recovery goal. |
| B-module | **TCCCKit stays in-memory-pure (no disk I/O).** All persistence lives in an app-layer `EncounterStore` **actor**. TCCCKit gains only a minimal *restore seam* (seed an engine from a loaded log, resuming id counters). | RF Ghost / no-I/O-in-the-logic-kit; mirrors the apply-path boundary (app owns I/O). |
| B-preserve | **New Casualty / End Care archive the encounter** (finalize + index, no data loss); **WIPE hard-purges the whole `encounters/` tree** with a post-delete `!exists` assertion. | The user's prior OPSEC call (apply-path cycle): retained archive ends accidental loss; explicit WIPE stays a deliberate sanitization of everything. |
| B-id | **Casualty timing/identity lives in the manifest**, not `PatientState`. Directory = `encounters/<casualtyId>_<unixStart>/`. | Keeps the domain model — and the 752 A-cycle equivalence tests — untouched; gives the dir a stable, collision-resistant, medico-legally-meaningful name. |
| B-noUI | **No archive-browsing UI this cycle.** The archive is write-only (audit/handoff retention). | Per CLAUDE.md §9 deferral; a future multi-casualty switcher reads the manifest. |
| B0 | **The key-set fix is task one** (before any persistence). | Replay-on-launch depends on `project(log)` reconstructing the exact patient key-set; B0 makes that structural. |

## 3. The B0 key-set fix (task one, TCCCKit)

The whole-branch review flagged: `project(log)` only creates a patient row for patients that appear in a `deterministicFact`/`operatorAcceptedFact` event; the imperative path can create a fact-less row via `ensurePatientExists`. Today they never diverge (a switched-to patient always gets timestamp deltas), but replay must not lean on that coupling.

**Fix (2 parts, ~6 lines):**
1. `PatientStateEngine.ensurePatientExists(_:timestamp:)` — when it *creates* a new patient (the `patients[pid] == nil` branch), append `.lifecycle(.init(id: "lc-\(lifecycleCount)", patientId: pid, timestampUnix: <processing ts>, kind: .encounterStarted))` to the log (new `lifecycleCount` counter; init's seed is `lc-1`). The processing timestamp is threaded from the call site (`processTranscript` has it; the record methods pass theirs) — keeps it medically meaningful and deterministic under a fixed clock.
2. `project` — replace `case .asrSegment, .operatorRejectedFact, .lifecycle: continue` so that `.lifecycle` with `kind == .encounterStarted` calls `ensure(p.patientId)` before `continue`; `.encounterEnded`/`.archived` stay inert. Now the projected key-set always matches the imperative dict, fact-less rows included.

`testProjectionReconstructsSwitchedPatientKeySet` (from the A whole-branch fix) keeps passing; add a test that a **fact-less** patient switch still reconstructs the row (the case that was only incidentally covered before).

## 4. Architecture

```
 LAUNCH                                         LIVE CARE                          HANDOFF / WIPE
 ──────                                         ─────────                          ──────────────
 TCCC_IOSApp.task                               AppState (MainActor)               AppState
   → store.loadActiveEncounter()                  await engine.processTranscript     newPatient()/endCurrentCare()
       reads manifest → active casualty             / recordOperatorAcceptedFact       → store.archive(activeId)
       reads events.jsonl (corrupt-tail safe)     → await persistNewEvents():          → store.startNewCasualty()  (newPatient only)
       → EncounterLog                                 log = await engine.snapshotLog()  wipeSession()
   → engine.restore(log)  [TCCCKit seam]              new = log.events[cursor...]        → store.purgeAll() + assert !exists
       patients = project(log); counters resume      await store.append(new, toActive)
   → cursor = log.events.count                        cursor = log.events.count
   → primaryPatient = project[...]
```

- **`EncounterStore` (app-layer `actor`)** — owns `Documents/encounters/`, the manifest, and all FileHandle I/O. Serial actor ⇒ ordered, off-MainActor writes. API:
  - `func append(_ events: [EncounterEvent], toCasualty id: String) async throws`
  - `func loadActiveEncounter() async throws -> (casualtyId: String, log: EncounterLog)?`
  - `func startNewCasualty(id: String, startUnix: Double) async throws`
  - `func archiveActive() async throws`
  - `func purgeAll() async throws` (deletes the tree; caller asserts `!exists`)
  - Injectable `baseURL` (defaults to `Documents`) for test isolation.
- **`ProtectedWrite.appendLine(_ line: String, to url: URL)`** (new, app-layer) — ensure parent dir exists (created with `.fileProtectionKey: .complete`), `createEmpty` the file if absent, `FileHandle(forWritingTo:)` → `seekToEnd` → `write(utf8 + "\n")` → `close` → `markProtected`. One JSON-encoded `EncounterEvent` per line.
- **Manifest** — `Documents/encounters/manifest.json`, app-layer `Codable`:
  ```
  { schemaVersion: 1,
    activeCasualtyId: String?,
    encounters: [ { casualtyId, dirName, startUnix, endedUnix?, archivedUnix?, status: active|archived } ] }
  ```
  Source-of-truth is the per-casualty `events.jsonl`; the manifest is a rebuildable index. On a manifest/log desync (crash between log append and manifest update), the log wins — `loadActiveEncounter` trusts the on-disk events.
- **Engine restore seam (TCCCKit)** — `PatientStateEngine.restore(_ log: EncounterLog)` (actor method) or an `init(passes:…, restoredLog:)`: sets `log = restoredLog`, `patients = Self.project(restoredLog)`, and resumes `asrCount`/`factCount`/`opCount`/`lifecycleCount` from the **count of each event type** in the restored log (ids are sequential, so count == max). `currentPatientID` = the patientId of the last `asrSegment` (or `PATIENT_1`). No disk knowledge enters TCCCKit.
- **Engine lifecycle marker (TCCCKit)** — `PatientStateEngine.recordLifecycle(_ kind: LifecyclePayload.Kind, timestamp:)` (actor method) appends a `.lifecycle` event (next `lc-` id) so End Care / archival leave an audit marker in the log itself. `project` ignores `.encounterEnded`/`.archived` for state (only `.encounterStarted` ensures a row).
- **Continuous persistence** — `AppState.persistNewEvents() async` reads `engine.snapshotLog()`, slices `events[persistedCursor...]`, appends them via the store, advances the cursor. Called after every engine mutation (`processWithEngine`, `acceptGraniteFact`, `rejectGraniteReviewItem`). On restore, the cursor is initialized to the loaded count so replayed events aren't re-written.

## 5. Lifecycle wiring (PRESERVE / PURGE)

Current bodies (verbatim from grounding) destroy in-memory state and reassign `engine = .standard()`. B keeps that in-memory reset **and adds archival around it**:

Ordering matters — the active log is already fully on disk from continuous persistence, so archival only adds an end-marker and flips manifest status:

- **`newPatient()`** — (1) `await engine.recordLifecycle(.archived, …)` then `await persistNewEvents()` (flush the marker to the *old* casualty's file); (2) `await store.archiveActive()` (manifest: status→archived, set `archivedUnix`); (3) `casualtyCounter += 1`; (4) `await store.startNewCasualty(newId, startUnix)`; (5) `engine = .standard()` (seeds `lc-1` + PATIENT_1); (6) `persistedCursor = 0`; (7) `await persistNewEvents()` (flush the new log's seed to the new file); (8) the existing in-memory reset.
- **`endCurrentCare()`** — (1) `await engine.recordLifecycle(.encounterEnded, …)` + `await persistNewEvents()`; (2) `await store.archiveActive()`; **does not** open a new casualty (no counter increment) — leaves a clean slate. (Preserves the existing new-vs-end UX distinction.)
- **`wipeSession()`** — `await store.purgeAll()`; assert `!FileManager.fileExists(atPath: encountersDir)` (a silent delete failure must not read as success); then the existing in-memory reset (which includes a fresh engine; its seed persists once the new dir is recreated by the next `startNewCasualty`/`persistNewEvents`).
- **`ConfirmationAction.detail`** copy flips from "clears current state" → "archives this casualty"; WIPE copy makes the total-purge explicit.

## 6. Task outline (writing-plans expands to TDD; ordering from the grounding)

- **B0.** Key-set fix: lifecycle-on-create + `project` ensures rows (TCCCKit). Tests: fact-less switch reconstructs row; 752 stay green.
- **B1.** `ProtectedWrite.appendLine` (app). Tests: file created with `NSFileProtectionComplete`, dir created protected, line round-trips, idempotent re-mark.
- **B2.** `EncounterStore` actor: JSONL append + per-casualty dir + manifest read/write/update (app). Tests against an injected temp `baseURL`: append→read round-trip; manifest reflects status; corrupt-tail (truncate mid-JSON) load skips the partial line and replays the rest.
- **B3.** Engine **restore seam + lifecycle marker** (TCCCKit): `restore(log:)` — `project` + counter resume + `currentPatientID`; and `recordLifecycle(_ kind:timestamp:)` (used by B6). Tests: restore(snapshotLog of a processed engine) reproduces `snapshot()`; a subsequent `processTranscript` emits non-colliding ids; `recordLifecycle(.encounterEnded)` appends an inert (state-preserving) marker.
- **B4.** **Continuous persistence** wiring: `AppState.persistNewEvents()` + cursor + calls after each engine mutation; `AppState.documentsURL`/store injectable (app). Tests: after a `processTranscript`, the active `events.jsonl` contains the new events; cursor advances; no duplicates.
- **B5.** **Replay-on-launch**: `store.loadActiveEncounter` + `AppState.load()` + the `TCCC_IOSApp` `.task` hook (app). Tests: write a partial encounter, construct a fresh AppState pointed at the same dir, `load()`, assert `primaryPatient` equals the pre-crash projection.
- **B6.** **Lifecycle PRESERVE/PURGE** rewrite (app): newPatient/endCurrentCare archive-and-rotate; wipeSession purge + `!exists` assertion; `ConfirmationAction` copy. Tests: newPatient preserves the prior casualty's file + starts a fresh one; wipe deletes the tree (post-assertion fires); `LifecycleAffordanceTests` copy updated.
- **B7.** Whole-branch review + manual device validation of PRESERVE (no data loss, manifest correct) and PURGE (files gone) on the iPhone 17 Pro — file protection is weaker on the simulator, so encryption-at-rest is device-verified.

## 7. Acceptance gate

1. **All TCCCKit + app tests green** at every task boundary (752 TCCCKit baseline + B0 additions; app baseline 72 + new persistence tests).
2. **Continuous durability**: after any committed event, that event is on disk before the next; a simulated crash (drop the in-memory engine, reload from disk) reproduces the projection.
3. **Corrupt-tail tolerance**: a JSONL truncated mid-line loads to the last complete event.
4. **Encryption at rest**: every written file + dir carries `NSFileProtectionComplete` (asserted in tests; **device-validated** in B7).
5. **PRESERVE**: New Casualty / End Care never delete a prior casualty's `events.jsonl`.
6. **PURGE**: WIPE removes the entire `encounters/` tree; the post-delete `!exists` assertion gates the "complete" signal.
7. **Invariant intact**: LLM-never-mutates and `snapshot() == project(log)` still hold (re-verified in B7).

## 8. Risks & mitigations (from grounding)

| Risk | Mitigation |
|---|---|
| `NSFileProtectionComplete` not re-asserted after `FileHandle.close` on iOS | `appendLine` always calls `markProtected` after close; **device-validated** in B7 (sim semantics are weaker). |
| Dir protection doesn't inherit to children | Create the dir with `.fileProtectionKey: .complete` AND `markProtected` each file. |
| Crash between log-append and manifest-update → manifest desync | Manifest is a rebuildable index; `loadActiveEncounter` trusts the on-disk `events.jsonl`, not the manifest's optimism. |
| Replayed ids collide with new events | `restore` resumes all counters from per-type event counts in the loaded log. |
| Persistence blocks MainActor | `EncounterStore` is a serial `actor`; appends are `await`ed off-main, ordered. |
| Tests pollute the device / leak files | All persistence tests inject `FileManager.temporaryDirectory` sub-dirs and clean up in `tearDown`. |
| B0 lifecycle events surprise a log-asserting test | `project` ignores them for state; log assertions use `contains`; run full suite at B0. |

## 9. Reuse inventory — do NOT rebuild

`ProtectedWrite` (extend with `appendLine`); `EncounterEvent`/`EncounterLog`/`PatientStateDelta` (already `Codable`); `PatientStateEngine` + `project`/`diff` (fold intact, add restore); `ConfirmationAction` (copy only); the three lifecycle methods (rewrite internals, keep external API); `DiagnosticsLogger` FileHandle-streaming pattern; the scenario fixtures (reuse for replay round-trip tests); `JSONEncoder`/`JSONDecoder` (`.secondsSince1970` for timestamps).

## 10. Out of scope (B)

Archive-browsing / multi-casualty UI; capacity bounds / log rotation / compaction; per-sentence evidence (A whole-branch #2); incremental projection cache; adding fields to `PatientState`; the workflow engine (C). A `schemaVersion` field is written for forward-compat but no migration logic is built (V1 only).
