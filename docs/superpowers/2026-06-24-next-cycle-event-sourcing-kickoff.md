# Next Cycle Kickoff — Event-Sourcing + Durable Retained Archive

**Date:** 2026-06-24
**Status:** PRE-BRAINSTORM roadmap (not a spec or plan yet — those get authored at run start)
**Predecessor:** the reconciliation apply path, shipped to `main` @ `89de5e8` this session.
**This cycle = the deferred north star** in `docs/superpowers/specs/2026-06-24-reconciliation-apply-path-design.md` §7.

---

## 0. Where we are (carry-over)

- `main` @ `89de5e8`, clean, **not pushed**. TCCCKit **726/0**, app target **67/0**, full sim build green.
- Decisions already made (locked): **A=yes** full event-sourcing is the target · durability = **retained archive** · **B=yes** apply path (done) · **C=defer** workflow engine (still deferred — NOT this cycle) · **D** Codex owns the audio lane · sequencing = visible-value-first (apply path shipped as direct mutation; **this cycle retrofits it onto the event spine**, rework knowingly accepted).
- The apply path that exists now is what we are RE-WIRING: `acceptGraniteFact` (in `TCCC_IOS/Intelligence/GraniteReviewQueue.swift`) currently does a **direct** `engine.apply([PatientStateFieldWrite], to:)`. This cycle makes that emit an event the reducer folds.

## 1. Goal & scope

**Goal:** make the immutable `EncounterEvent` log the canonical memory, with `PatientState` a deterministic projection (fold) of that log; persist the log encrypted; retain past casualties as a durable archive; re-derive evidence linkage from events.

**IN scope:**
- `EncounterEvent` type + append-only `EncounterLog` (canonical record).
- Reducer folds events → `PatientState` (reusing the existing extractor passes + `PatientStateFieldWrite`).
- Apply path emits `.operatorAcceptedFact` events instead of direct mutation.
- Durable, encrypted (`NSFileProtectionComplete`) per-casualty event log + **retained archive** of past casualties.
- Replay-on-launch (crash recovery for the in-progress casualty).
- Lifecycle semantics: **new-casualty PRESERVES** (archives the active encounter); **WIPE (HOLD-3s) PURGES the whole archive** — the affordance distinctness was pre-built in apply-path Task 8; this cycle lands the destructive semantics.
- Evidence-linkage re-derivation (replace the best-effort `evidenceIds: []` stopgap).
- Carried polish: enum-sync regression test (`FieldRouter` ↔ `PatientStateFieldWrite`), WIPE progress-bar `GeometryReader`, log-string consistency.

**OUT of scope (do not touch):**
- Workflow engine (C — deferred further).
- Audio lane: Granite Speech, `AudioFrameLedger`, chunked-encode — **Codex's** (`codex/sprint-2-audio-research`). Stay out of its worktrees.
- Multi-casualty UI (the archive is multi-casualty by nature, but the live UI stays single-casualty; the foreign-patient accept guard from last cycle stands).

## 2. Recommended decomposition — split into TWO shippable sub-cycles

This is large and the reducer re-point is risky. Recommend NOT doing it as one run:

- **Sub-cycle A — Event-sourcing core (in-memory):** `EncounterEvent` + `EncounterLog`; reducer folds events; equivalence-proven re-point so `PatientState` becomes a projection; apply path emits events; evidence re-derivation. **No persistence yet** — log is in-memory canonical. Ships with 726+ green.
- **Sub-cycle B — Durable archive:** persist the log (encrypted JSONL per casualty); replay-on-launch; retained archive + index; WIPE-purges-archive semantics; new-casualty-archives semantics.

Each is independently shippable and reviewable. **Brainstorming should confirm this split** (or merge if the user wants one run). The rest of this doc plans both; if split, run A first.

## 3. The hard part, named honestly

1. **Reducer re-point without breaking 726 TCCCKit tests.** Those tests assert `processTranscript(text) → PatientState`. If the engine starts folding an event log instead, the *external contract must be byte-identical*. De-risk with an **equivalence test** (fold-the-log result == imperative result) BEFORE making the fold authoritative.
2. **Module boundaries.** The reducer (`PatientStateEngine`) lives in **TCCCKit**; it must fold events, so `EncounterEvent` likely lives in TCCCKit. But event payloads reference app-target types (`TranscriptSegment` in `TCCC_IOS/Audio/`, `GraniteCandidateFact`/`DeterministicFact` in `TCCC_IOS/Intelligence/`). Same boundary tension we solved for the apply path (`FieldRouter` in app, `PatientStateFieldWrite` in TCCCKit). **Decide where `EncounterEvent` lives and what its payloads are.**
3. **Persistence of multi-casualty PHI.** The retained archive holds multiple casualties' protected health info on-device — encryption (`NSFileProtectionComplete`) is non-negotiable (hard constraint #3), and WIPE must be a genuine purge.
4. **Replay correctness + performance.** Folding a long encounter's log on launch must reconstruct state correctly and fast enough.

## 4. Design forks to resolve in BRAINSTORMING (the open questions)

1. **`EncounterEvent` schema & granularity.** Cases likely: `asrSegment` (transcript evidence), `deterministicFact` (engine extraction), `candidatePatchProduced` (LLM output, pre-validation), `operatorAcceptedFact` (the apply event), `conflictRaised`/`conflictResolved`, `lifecycle` (encounterStarted / cared-ended / archived), maybe `vitalsReading`, `manualEdit`. Each event: stable `id`, `timestamp`, `patientId`, payload, `sourceStage` (asr|deterministic|granite|human). How fine-grained?
2. **Module placement of `EncounterEvent`** (TCCCKit vs app) and payload representation (TCCCKit-native value types vs referencing app types). See §3.2.
3. **Reducer fold model.** Does `processTranscript` become "append asrSegment event → fold"? Is folding full-replay each time, or incremental (apply only the new event)? Where does sentence-tokenization/extraction sit relative to the event boundary (one event per sentence? per committed line?).
4. **Re-point strategy:** additive-dual-write-then-flip (recommended, §6) vs big-bang. Confirm.
5. **Persistence format & location.** Append-only JSONL per casualty under `Documents/encounters/<casualtyId>/events.jsonl`? `NSFileProtectionComplete` via the existing `ProtectedWrite` helper. Append-on-each-event vs batched flush. How is partial/corrupt tail handled on replay?
6. **Archive model.** How are archived casualties indexed/listed (a manifest)? Capacity bound / rotation? Does the live UI ever surface the archive (probably not this cycle — retention is for audit/handoff, not browsing)?
7. **Replay/crash-recovery trigger.** On launch, detect an in-progress (un-archived) encounter and replay it. How to mark "in-progress" vs "archived/handed-off"?
8. **Lifecycle semantics wiring.** `newPatient()` / `endCurrentCare()` currently wipe in-memory state — they must instead CLOSE+ARCHIVE the active encounter and start a fresh log. `wipeSession()` (WIPE HOLD-3s) must DELETE the whole `encounters/` archive. (Parity flag from last cycle was clean — no test enshrines the old destructive new-casualty behavior, so the preserve-semantics change is unblocked.)
9. **Evidence linkage.** `operatorAcceptedFact` / `deterministicFact` events reference the `asrSegment` event id(s) that produced them, replacing `evidenceIds: []`. How is the linkage computed at extraction time?
10. **Invariant preservation.** LLM-never-mutates-state must STILL hold: an LLM-origin fact reaches state only as an `operatorAcceptedFact` event (post validation + `OperatorAcceptedFact` guard + `FieldRouter`); the reducer folding that event reuses `PatientStateFieldWrite`. No new mutation path.

## 5. Recommended architecture (concrete proposal — brainstorm refines)

- **`EncounterEvent`** — `enum` (Codable, Sendable) in **TCCCKit** (`TCCCDomain`), with TCCCKit-native payloads. Where a payload needs an app-only type, store the minimal projected fields (e.g. an event carries `(domain, field, value, evidenceIds)` not the whole `GraniteCandidateFact`). Each case wraps a small struct with `id`, `timestampUnix`, `patientId`.
- **`EncounterLog`** — append-only value type in TCCCKit holding `[EncounterEvent]` (mirrors today's `TranscriptSegmentLedger` shape: `private(set)` storage + `append`). One log per casualty.
- **Reducer** — `PatientStateEngine` gains `func project(_ log: EncounterLog) -> [String: PatientState]` (or per-patient) that folds events: `asrSegment` → run the existing 11 extractor passes (reuse current logic); `operatorAcceptedFact` → apply via the existing `PatientStateFieldWrite` path; `deterministicFact` → same. `processTranscript` becomes a thin adapter: append `asrSegment` events, then project.
- **Persistence** — `EncounterStore` (app target) writes each appended event to `Documents/encounters/<casualtyId>/events.jsonl` via `ProtectedWrite` (`NSFileProtectionComplete`); reads+folds on launch.
- **Archive** — `Documents/encounters/` is the retained archive; a `manifest.json` indexes casualties. `newPatient`/`endCurrentCare` finalize the current log + start a new dir; WIPE deletes `encounters/`.
- **Apply path retrofit** — `acceptGraniteFact` appends an `operatorAcceptedFact` event (after the same validation/guard/contradiction checks) instead of calling `engine.apply` directly; the reducer folds it. The foreign-patient guard and contradiction routing remain.

## 6. Proposed task breakdown (TDD, sequenced; "A" = sub-cycle A, "B" = sub-cycle B)

**A1.** `EncounterEvent` enum + `EncounterLog` (append-only) in TCCCKit. Tests: append/immutability/codable round-trip. *Additive, no behavior change.*
**A2.** Reducer `project(log) -> PatientState`: fold `asrSegment` events through the existing extractor passes. Test: a log of asr events projects the SAME `PatientState` as `processTranscript` over the same text — the **equivalence test** (the key de-risker).
**A3.** Fold `operatorAcceptedFact` + `deterministicFact` events (reuse `PatientStateFieldWrite`/`FieldRouter`). Tests: an accepted-fact event mutates the projection through the engine.
**A4.** Dual-write (additive): every current input ALSO appends an event to a live `EncounterLog` on `AppState`; engine behavior unchanged; all 726+67 tests stay green. *Log built but not yet canonical.*
**A5.** Flip to canonical: `PatientState` is derived from the log (`project`); `processTranscript` → append+project. Equivalence test (A2) guards the flip. The 726 tests must stay green.
**A6.** Apply-path retrofit: `acceptGraniteFact` appends `operatorAcceptedFact` (keeps validation + `OperatorAcceptedFact` + contradiction + foreign-patient guards). Re-run last cycle's apply/conflict tests — still green.
**A7.** Evidence re-derivation: fact events carry real `evidenceIds` referencing `asrSegment` event ids. Replace the `evidenceIds: []` stopgap. Test the linkage.
**A8.** Polish carried from last cycle (enum-sync regression test; log-string consistency).

**B1.** `EncounterStore`: encrypted append-only JSONL per casualty via `ProtectedWrite` (`NSFileProtectionComplete`). Tests: file written with protection attribute; round-trips.
**B2.** Replay-on-launch: reconstruct `PatientState` from the persisted log; corrupt-tail tolerance. Tests.
**B3.** Retained archive + manifest index; `newPatient`/`endCurrentCare` archive-and-rotate (PRESERVE semantics). Tests: prior casualty's log survives a new-casualty.
**B4.** WIPE purges the archive (HOLD-3s affordance already exists from apply-path Task 8 — wire the destructive delete of `encounters/`). Confirmation + test that the archive is gone.
**B5.** WIPE progress-bar `GeometryReader` polish.

## 7. Methodology / process steps for the run

1. **Pre-flight:** `git log --oneline -5` (confirm main @ 89de5e8); confirm build-env (§9); baseline `swift test` (726) + full app suite green; **branch a fresh feature branch** off main (e.g. `event-sourcing-core`) — never work on main.
2. **Brainstorm** (`superpowers:brainstorming`): resolve the §4 forks WITH the user (one question at a time); confirm the A/B split; produce a **design spec** in `docs/superpowers/specs/2026-06-2X-event-sourcing-design.md`; spec self-review; user review gate.
3. **Write the per-task TDD plan** (`superpowers:writing-plans`) → `docs/superpowers/plans/2026-06-2X-event-sourcing-core.md` (and a second for archive). Ground exact type shapes first (a short read-only research pass over the current engine/ledger/ProtectedWrite/lifecycle).
4. **Execute** (`superpowers:subagent-driven-development`): implementer + two-stage review per task, fix loops, durable ledger at `.superpowers/sdd/progress.md`. Use the §9 build commands. The **equivalence test (A2) gates the re-point (A5)** — do not flip canonical until A2 is green.
5. **Whole-branch review** on opus — specifically re-verify the LLM-never-mutates invariant survives the event retrofit, and that the reducer flip preserves the engine contract.
6. **Merge** (option 1, local) on the user's say-so. Push/PR only when asked.

## 8. Constraints / invariants / risks

- **Keep 726 TCCCKit + 67 app tests green throughout.** The A5 reducer flip is the highest-risk step; A2's equivalence test is the safety net — author it first.
- **LLM-never-mutates-state must remain structural** after the retrofit (events carrying LLM-origin facts still pass validation → `OperatorAcceptedFact` → `FieldRouter` → `PatientStateFieldWrite`).
- **RF Ghost** (no networking). **AES-256 / `NSFileProtectionComplete`** on the log + archive (multi-casualty PHI at rest). **Gloved-hand** UI, landscape, NVG-safe tokens.
- **Engine stays sole writer of `PatientState`** — now via folding events, but no new external mutation path.
- **Scope fence:** no workflow engine; no audio lane (Codex).
- **Risk:** archive growth / disk (machine had ~23 GB free after the platform install — watch it; the platform DL consumed ~8.5 GB).

## 9. Build-env & verification (carry forward — saves ~1.5 h of re-debugging)

- App sim build needs the **iOS 26.4.1 simulator runtime** (installed this session). If a fresh machine: `xcodebuild -downloadPlatform iOS`.
- **App test/build destination MUST be:** `-destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E'`. The bare `id=…` and `generic/platform=iOS Simulator` forms FAIL ("Supported platforms … is empty") because of the connected iPhone's device-platform.
- **Class-level `-only-testing:Target/Class` reports 0 tests** on this sim — use `Target/Class/method` or a full-suite run.
- App test cmd: `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:...`
- TCCCKit: `cd /Users/ama/TCCC_IOS/Packages/TCCCKit && swift test`. `-skipMacroValidation` always required for app builds. New files: implementers must `git add TCCC_IOS.xcodeproj/project.pbxproj` (xcodegen regenerates it).

## 10. Key files / symbols in play

- TCCCKit: `PatientStateEngine.swift` (the reducer — gains `project`), `PatientStateFieldWrite.swift`, `ExtractorPass.swift` + the 11 extractors, `PatientState/MARCHState/Vitals/PAWSAssessment`. New: `EncounterEvent.swift`, `EncounterLog.swift`.
- App: `TCCC_IOS/App/AppState.swift` (integration hub — lifecycle `newPatient`/`endCurrentCare`/`wipeSession`, `graniteReviewQueue`, the live log), `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (`acceptGraniteFact` — retrofit to emit events), `TCCC_IOS/Audio/TranscriptSegmentLedger.swift` (the existing transcript ledger — the seed to generalize), `TCCC_IOS/App/ProtectedWrite.swift` (the `NSFileProtectionComplete` write helper for persistence), the `Intelligence/` hot-seat types, `Components/FooterHints.swift` + WIPE affordance (Task 8).
- Reference: `docs/superpowers/specs/2026-06-24-reconciliation-apply-path-design.md` §7 (the north star), `docs/superpowers/specs/2026-06-24-harness-reconciliation.md` (the original recon), `docs/granite/GRANITE_HOT_SEAT_ARCHETYPE.md` (the EncounterEvent/AudioFrameLedger vision the user's GPT design echoed).

## 11. First concrete actions on resume (post-compaction)

1. Read this doc + `.superpowers/sdd/progress.md` (last cycle's ledger) + the apply-path design spec §7.
2. `git status` / `git log --oneline -5` → confirm main @ 89de5e8 clean.
3. Confirm build-env per §9 (a quick `swift test` + one `-only-testing` app test on the working destination).
4. Branch `event-sourcing-core` off main.
5. Invoke `superpowers:brainstorming` to resolve the §4 forks (confirm the A/B split first).
6. Proceed: spec → plan → subagent-driven execution → review → merge.
