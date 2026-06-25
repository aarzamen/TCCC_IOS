# Harness Architecture Reconciliation — Event-Sourced Design vs. Repo Reality

**Date:** 2026-06-24
**Author:** recon pass (read-only)
**Repo state at analysis:** `main` @ `87a17eb` (`docs(audio): record sprint 2 chunked-encode research blocker`), clean tree (two untracked scratch files: `layout_playground.html`, `tccchell.pdf`)
**Status of this document:** **RECONNAISSANCE — not a plan, not an approval to build.** It maps a proposed architecture onto the code as it exists today so that real per-sprint prompts can be written from facts instead of from a greenfield assumption.

> **Placement note.** The instruction named `docs/superpowers/plans/harness-refactor-reconciliation.md`, with permission to follow the repo convention instead. The convention here is: `docs/superpowers/specs/*-design.md` holds the *architecture/design source* that the `docs/superpowers/plans/*.md` per-task TDD plans are derived from (e.g. `2026-05-07-granite-hot-seat-design.md` → `2026-05-07-granite-hot-seat.md`). Because this document "becomes the actual spec we write the per-sprint prompts from," it belongs with the design specs, not the per-task plans. Filed here accordingly. Say the word and it moves to `plans/`.

---

## 0. The one question

How does the proposed **event-sourced harness architecture** —

1. immutable `EncounterEvent` ledger as canonical memory,
2. deterministic reducer as sole projection authority,
3. deterministic + LLM candidate producers feeding a reconciliation boundary,
4. LLM-never-mutates-state invariant,
5. deterministic workflow engine,

— map onto the repo **as it exists today**: the superpowers sprint methodology, the current `docs/superpowers/` and `docs/specs/` structure, the completed Granite Sprint 1, and the in-flight Sprint 2?

For each piece: **already built / partially built (and where) / in flight (under which sprint) / genuinely not started**, with exact files and symbols, fact separated from recommendation.

### Method & provenance (so this is auditable)

- 5 architectural pieces each read by a dedicated read-only agent, then each finding adversarially re-verified by a second agent that opened every cited file to confirm the symbol exists (10 agents, ~671k tokens, 315 tool calls). Workflow run `wf_3cfedc8a-291`.
- The three load-bearing files (`PatientStateEngine.swift`, `TranscriptSegmentLedger.swift`, `AppState.swift`) were additionally read first-hand by the author; readings match the verified agent output.
- One hallucinated citation was caught and removed: `DeterministicFact` was claimed to live in a standalone `DeterministicFact.swift`; it is actually defined in `TCCC_IOS/Intelligence/HotSeatPacket.swift:25`. Every other cited symbol was confirmed present.

### Out of scope (hard boundary)

- **Granite *Speech* / audio ingestion** (the G0–G4 ASR sprint and its in-flight Sprint 2 chunked-encode work) is **owned by Codex** (`codex/sprint-2-audio-research`). This document does not analyze, recommend changes to, or touch that lane. Where the harness depends on it (audio → ledger), that edge is marked **[CODEX/AUDIO — out of scope]** and left alone until Sprint 2 signs off in `docs/granite/SPRINT_BOARD.yaml`.
- No code was written or modified. The only artifact produced is this document.

### A naming clarification that matters

There are **two parallel "Sprint 1 / Sprint 2" lineages** in the repo; conflating them produces wrong status calls:

| Lineage | Source of truth | What it is | State |
|---|---|---|---|
| **Granite hot-seat** | `docs/granite/SPRINT_BOARD.yaml`, `docs/superpowers/plans/2026-05-07-granite-hot-seat*.md` | ledger → packet → validator → review queue → candidate patch (the *structure* side) | GHS-01…05 + GHS2-01…06 mostly `implemented`. **This is where the harness architecture already lives.** |
| **Granite *Speech*** | `docs/specs/v3_sprint_1_granite_foundation.md`, `SPRINT_1_ACCEPTANCE.md` | replace ASR placeholder with on-device `mlx-audio-swift` transcription (the *audio* side) | Sprint 1 signed off 2026-05-10 (7 PASS / 1 PARTIAL / 1 DEFERRED). Sprint 2 = chunked-encode, **in flight, Codex's lane.** |

Everywhere below, "the hot-seat sprint" = the structure lineage. "[CODEX/AUDIO]" = the speech lineage.

---

## 1. TL;DR — the five pieces at a glance

| # | Proposed piece | Status | It already exists as | The real gap |
|---|---|---|---|---|
| 1 | Immutable `EncounterEvent` ledger (canonical memory) | **Partial → mostly not-started** | `TranscriptSegmentLedger` (transcript-only) | No `EncounterEvent` type, no unified log, canonical memory is scattered mutable state |
| 2 | Deterministic reducer (sole projection authority) | **Partial — strongest match** | `PatientStateEngine` + `ExtractorPass` | Folds transcript *strings*, not an event log; state accumulates mutably inside the actor |
| 3 | Deterministic + LLM producers → reconciliation boundary | **Partial** | extractors + `GraniteHotSeatGenerator` + `GraniteSchemaValidator` + `graniteReviewQueue` | **No apply path**; deterministic facts not fed in; no operator review UI; no conflict resolution |
| 4 | LLM-never-mutates-state | **Held today (effectively built)** | return-type discipline + no apply path + `INSTRUCTIONS_FOR_AGENTS` | Enforced partly *by absence*; durability depends on how piece 3's apply path is built |
| 5 | Deterministic workflow engine | **Not started (as an engine)** | imperative glue in `AppState`; two embedded mini-orchestrators | No unified gated pipeline runner sequencing the stages |

**Headline:** the proposed "event-sourced harness" is roughly **40% already present under the Granite hot-seat vocabulary**. The producer/validator/review-queue boundary and the LLM-never-mutates invariant are real and working. What is genuinely missing is narrow and specific: a true event log (if event-sourcing is actually wanted), the **candidate→state apply/reconcile path**, **feeding deterministic facts into the packet**, and a **workflow-engine abstraction**. A five-session greenfield plan would rebuild a large amount of code that already exists and is tested.

---

## 2. Vocabulary reconciliation (the highest-value section)

The proposed design and the repo describe the same shape in different words. Mapping them is what prevents a greenfield rebuild.

| Proposed (event-sourced) term | Repo symbol(s) today | Exists? | File |
|---|---|---|---|
| `EncounterEvent` (event type) | — | **Absent** | only named in `GRANITE_HOT_SEAT_ARCHETYPE.md` §Principle 1 |
| `AudioFrameLedger` | — | **Absent** | named in `granite_pipeline_contract.yaml:28` + archetype doc, no code |
| EncounterEvent **ledger** (canonical memory) | `TranscriptSegmentLedger` (transcript-only) | **Partial** | `TCCC_IOS/Audio/TranscriptSegmentLedger.swift:30` |
| transcript **segment** | `TranscriptSegment` | Yes | `TranscriptSegmentLedger.swift:19` |
| deterministic **fact** | `DeterministicFact` | Yes (but unused — see §3.3) | `TCCC_IOS/Intelligence/HotSeatPacket.swift:25` |
| LLM **candidate** fact / patch | `GraniteCandidateFact` / `GraniteCandidatePatch` | Yes | `HotSeatPacket.swift:47`, `:66` |
| `@Generable` candidate DTO | `GraniteGeneratedCandidatePatch` | Yes | `TCCC_IOS/Intelligence/GraniteGeneratedCandidatePatch.swift:92` |
| input **packet** envelope | `HotSeatPacket` + `HotSeatPacketBuilder` | Yes | `HotSeatPacket.swift:36`, `HotSeatPacketBuilder.swift:4` |
| deterministic **reducer** | `PatientStateEngine` | Yes | `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift:33` |
| reducer **step** (fold fn) | `ExtractorPass.apply(_:context:)` | Yes | `ExtractorPass.swift:54` |
| projected **state** | `PatientState` (value type) | Yes | `Packages/TCCCKit/Sources/TCCCDomain/PatientState.swift:15` |
| **reconciliation boundary** (validator) | `GraniteSchemaValidator` → `GraniteValidationResult` | Yes (validate only) | `GraniteSchemaValidator.swift:20`, `:51` |
| review/patch **queue** | `graniteReviewQueue: [GraniteReviewItem]` | Yes (in-memory only) | `AppState.swift:452`, `GraniteReviewQueue.swift:8` |
| candidate → state **apply** | — | **Absent** | the central gap (§3.3) |
| LLM **backend** boundary | `TCCCLLMBackend` + 5 backends | Yes | `TCCC_IOS/Intelligence/TCCCLLMBackend.swift:34` |
| deterministic **workflow engine** | — (imperative glue in `AppState`) | **Absent as an engine** | `AppState.appendFinal:454`, `runGraniteHotSeatReview:24` |

---

## 3. Per-piece detail

Each section separates **FACT** (read from code/docs, cited) from **RECOMMENDATION** (inference about what reconciliation implies). Recommendations are advisory only.

### 3.1 — Immutable `EncounterEvent` ledger as canonical memory → **PARTIAL → mostly NOT-STARTED**

**FACT — what exists.**
- `TranscriptSegmentLedger` is a value-type (`struct … Sendable, Equatable`) append-only store of ASR transcript segments — raw + normalized, with quality flags (`duplicateCollapsed`, `instructionLikeContent`, …). Mutation is via `mutating func appendRaw(…)`; there is no remove. `TCCC_IOS/Audio/TranscriptSegmentLedger.swift:30`, `:34`.
- It records **transcript segments only** — not deterministic facts, candidate patches, vitals, interventions, lifecycle events, or accepted state. `TranscriptSegment` fields at `:19`.
- The **de-facto canonical memory** today is split across mutable holders: `AppState`'s `@Observable` fields (`transcript`, `primaryPatient`, `allPatients`, `vitalsLog`, `graniteReviewQueue`, `encounterNarrative`, …) at `AppState.swift:415–452`, plus the engine's internal `patients` dict at `PatientStateEngine.swift:38`.
- `GraniteReviewItem` queue is an in-memory `AppState` property; it is wiped on `newPatient()` / `endCurrentCare()` / `wipeSession()` and never persisted to disk. `AppState.swift:452`, `:662`, `:693`, `:723`.

**FACT — what is absent.**
- No `EncounterEvent` type (the proposed enum over `asr | deterministic | granite_hot_seat | human_edit`) exists in Swift. It appears only in `GRANITE_HOT_SEAT_ARCHETYPE.md:24–30`.
- No `AudioFrameLedger` exists in code — it is named as a pipeline stage output in `granite_pipeline_contract.yaml:28` and in the archetype data-flow `GRANITE_HOT_SEAT_ARCHETYPE.md:85`, with no implementation.
- No single append-only event log that is the source of truth for the whole encounter; no replay / re-derivation path.

**Status rationale.** The *ledger primitive* exists but is scoped to one event kind (transcript). The *canonical-memory / event-sourcing* property — one immutable log from which all state is a projection — is not present at all. Honest split: **ledger = partial; canonical-memory = not-started.**

**Sprint trace (FACT).** `TranscriptSegmentLedger` landed in the hot-seat sprint as task GHS-01 ("transcript segment ledger"). No active sprint owns a generalized event log.

**RECOMMENDATION.** Decide first whether full event-sourcing is actually wanted (see §6, Decision A). If yes, `TranscriptSegmentLedger` is the seed to *generalize*, not replace; `DeterministicFact`, `GraniteCandidateFact`, and a future `human_edit` event are the other event kinds.

### 3.2 — Deterministic reducer as sole projection authority → **PARTIAL (strongest match)**

**FACT — what exists.**
- `PatientStateEngine` (a Swift `actor`) is the deterministic producer of `PatientState`. `processTranscript(_:timestamp:)` normalizes → sentence-tokenizes → for each sentence threads state through every pass: `var current = patient; for pass in passes { current = pass.apply(current, context: context) }`. `PatientStateEngine.swift:79`, `:110`.
- The reducer **step** is already a pure fold: `protocol ExtractorPass { func apply(_ state: PatientState, context: ExtractionContext) -> PatientState }`. `ExtractorPass.swift:54`. Each extractor is `var s = state; …; return s` (e.g. `HemorrhageExtractor.swift:116`).
- `PatientState` is a **value type** (`struct … Sendable, Codable, Equatable, Hashable, Identifiable`), so projection copies are language-guaranteed. `PatientState.swift:15`.
- **The engine is the SOLE writer of `PatientState`.** `AppState` never mutates patient fields directly — it only *reads* via `engine.snapshot()` in `refreshPatientSnapshot()` (`AppState.swift:527`) and assigns `primaryPatient` / `allPatients`. Verified by reading the whole file first-hand: no direct `PatientState` field write exists in `AppState`.
- Standard dispatch order is fixed and documented (11 passes, MOI → … → Classification last). `PatientStateEngine+Standard.swift:33`.

**FACT — what is absent.**
- The engine folds a **transcript string**, not an event log. Its accumulated state lives mutably inside the actor (`patients` dict), not as a value re-derivable from a log.
- The upstream `AppState.transcript` is mutable and can be wiped or replaced (`transcriptCleaned`), so prior reducer outputs are not reconstructible from a canonical source.

**Status rationale.** The two properties the proposal cares about — *deterministic reducer* and *sole projection authority* — are genuinely present and are the codebase's biggest asset here. It falls short of **event-sourced** only because the input is a string stream and the accumulation is internal. Effectively **built for "sole authority"; partial for "event-sourced reducer."**

**Sprint trace (FACT).** Predates the hot-seat work — this is the original TCCCKit port of the Python `state.py` engine.

**RECOMMENDATION.** This is the part to *preserve and lean on*, not refactor. If event-sourcing is adopted, the change is to feed the reducer an event log instead of (or in addition to) raw strings — the `ExtractorPass` fold shape already fits a reducer-over-events model.

### 3.3 — Deterministic + LLM candidate producers → reconciliation boundary → **PARTIAL**

**FACT — what exists.**
- **Two producer paths.** Deterministic: 10 `ExtractorPass` conformers inside the engine. LLM: `GraniteHotSeatGenerator.candidatePatch(for:using:)` builds a prompt from a `HotSeatPacket`, calls a `TCCCLLMBackend`, and decodes a `GraniteCandidatePatch`. `GraniteHotSeatGenerator.swift:16`.
- **Packet envelope** combining both kinds of input exists: `HotSeatPacket { segments, deterministicFacts, knownPatientIds, allowedSchemas, blockedActions }`, built by `HotSeatPacketBuilder.build(…)`. `HotSeatPacket.swift:36`, `HotSeatPacketBuilder.swift:4`.
- **Reconciliation boundary (validation).** `GraniteSchemaValidator.validate(_:knownEvidenceIds:knownPatientIds:)` checks patient ids, field names, evidence-id existence, and value ranges, returning `GraniteValidationResult { acceptedFacts, conflicts, errors }`. `GraniteSchemaValidator.swift:51`.
- **Holding queue.** `applyGraniteCandidatePatchForReview(…)` validates a patch and appends a `GraniteReviewItem` to `graniteReviewQueue`; status is `.readyForOperatorReview` or `.heldForValidation`. `GraniteReviewQueue.swift:60`, `:8`.

**FACT — what is absent (the core gap).**
- **No apply path.** Nothing reads `graniteReviewQueue` and merges accepted `GraniteCandidateFact`s into `PatientState`. The queue is terminal. The integration test `testValidPatchIsQueuedForOperatorReviewWithoutMutatingState` *asserts* `state.primaryPatient == before` after a valid patch. `GraniteHotSeatIntegrationTests.swift:43`.
- **Deterministic facts are never fed in.** The single call site passes `deterministicFacts: []` hardcoded empty. `GraniteReviewQueue.swift:35`. So the "deterministic + LLM both feed the boundary" property is only half-wired: the LLM currently sees segments but no deterministic facts, and the engine's facts are not packaged as `DeterministicFact`s at all.
- **No operator review UI** surfacing the queue; **no conflict-resolution logic** (conflicts are flagged, never resolved/presented); no recency/correction rules applied.
- `SPRINT_BOARD.yaml` task **GHS-05** lists acceptance `accepting_patch_records_accepted_by` — that accept/merge path is **specified but not implemented**.

**Status rationale.** Producers + validator + holding queue: built. Apply + reconcile + operator review + deterministic-fact feed: not started. **Partial.**

**Sprint trace (FACT).** Built across hot-seat GHS-02/03/04 and GHS2-01/02 (all `implemented`). The missing apply/reconcile is the unfulfilled remainder of GHS-05 — not owned by any in-flight sprint today.

**RECOMMENDATION.** This is the highest-value harness-refactor target: (a) emit engine facts as `DeterministicFact`s into the packet; (b) build the accept→deterministic-merge apply path so an accepted candidate becomes a real `PatientState` mutation *through the engine/validator*, never the LLM; (c) add the operator review surface and conflict rules. See §6 Decision B.

### 3.4 — LLM-never-mutates-state invariant → **HELD TODAY (effectively built)**

**FACT — what exists.**
- The four prose generators return non-state types: `RadioScriptGenerator.generate(…) -> String` (`:45`), `ZMISTNarrativeGenerator.generate(…) -> String` (`:39`), `EncounterNarrativeGenerator.generate(…) -> String` (`:33`), `TranscriptCleaner.clean(_:) -> [TranscriptLine]` (`:44`). Their outputs land in display-only `AppState` fields (`encounterNarrative`, `zmistNarrative`, `transcriptCleaned`). None write `PatientState`.
- The backend protocol returns text only: `TCCCLLMBackend.generate(instructions:prompt:) async throws -> String`. `TCCCLLMBackend.swift:34`.
- The Granite hot-seat path produces `GraniteCandidatePatch` (a plain `Codable` value) → review queue, never state. The system prompt itself says *"Do not mutate app state, do not produce report prose, and do not download model weights."* `GraniteHotSeatGenerator.swift:17`. The guardrail is also documented: `INSTRUCTIONS_FOR_AGENTS.md:14`, with the required boundary shape at `:19`.
- Confirmed structurally by §3.2: `PatientState`'s only writer is the deterministic engine, whose only input is transcript text — there is no wire from any LLM output into the engine.

**FACT — the nuance.**
- The invariant is currently enforced by a **combination** of (a) return-type discipline (generators can't return `PatientState`) and (b) the **absence** of any candidate→state apply path. It is therefore partly true *by construction* and partly true *because the dangerous path doesn't exist yet*.
- The prose-generator boundary is API-contractual, not impossible-by-construction: a future edit could add a mutation inside a generator body (nothing structurally forbids it).

**Status rationale.** As an invariant about the code *today*, it is **enforced — effectively built.** I diverge from the recon agents' "partial" call here: nothing currently violates it. The honest caveat is durability, not present state.

**RECOMMENDATION.** The invariant's real test arrives when §3.3's apply path is built. Preserve it by routing accepted candidates *through* the deterministic engine/validator (candidate → validated fact → engine-mediated mutation), so the LLM still never writes state directly. Consider a type-level guard (e.g., the apply API accepts only `GraniteValidationResult.acceptedFacts`, never a raw patch) so the invariant is structural rather than conventional.

### 3.5 — Deterministic workflow engine → **NOT STARTED (as an engine)**

**FACT — what exists.**
- Two embedded **mini-orchestrators**: (a) `PatientStateEngine.processTranscript` runs the 11-pass extraction in fixed order; (b) `GraniteRealModelRunner.run(packet:backend:…)` runs prompt → `backend.generate` → parse → validate linearly in one async function with metrics. `GraniteRealModelRunner.swift:90`.
- `ReportPipeline.generateAll(from:at:)` exists but only runs the two fallback report generators (`medevac`, `zmist`) — it is a report selector, not a pipeline orchestrator. `ReportPipeline.swift:30`.

**FACT — what is absent.**
- No unified engine sequences the full pipeline (capture → ledger → extract → packet → adjudicate → validate → reconcile → review) as ordered, gated steps with retries/checkpoints. The stages are wired ad-hoc: `appendFinal` calls `appendTranscriptEvidence` (ledger) inline at `:472` and spawns `Task { processWithEngine }` at `:475`; `runGraniteHotSeatReview` is invoked separately, manually, later (`GraniteReviewQueue.swift:24`). No gates between stages; no stage-level retry.

**Status rationale.** The *stages* exist; the *engine abstraction that owns and sequences them* does not. **Not started** for the engine; stages mostly built.

**Sprint trace (FACT).** No sprint has scoped a workflow engine.

**RECOMMENDATION.** Lowest priority of the five. Only worth building if the apply/reconcile path (§3.3) plus event log (§3.1) are adopted — at that point a thin deterministic runner that sequences ledger-append → extract → packet → adjudicate → validate → reconcile, with explicit gates, is the natural home. Until then, the imperative glue in `AppState` is adequate and changing it is pure churn.

---

## 4. What's genuinely NOT started (consolidated, FACT)

1. `EncounterEvent` type and a unified immutable event log / canonical memory (§3.1).
2. `AudioFrameLedger` (§3.1) — **[CODEX/AUDIO — out of scope; do not build here].**
3. Candidate→`PatientState` **apply/merge** path (§3.3) — the central gap.
4. Packaging engine output as `DeterministicFact`s and feeding them into `HotSeatPacket` (currently `[]`) (§3.3).
5. Operator review UI for `graniteReviewQueue`; conflict-resolution logic (§3.3).
6. Persistence of the review queue / any event log (currently in-memory, wiped on lifecycle actions) (§3.1).
7. A deterministic **workflow engine** abstraction (§3.5).

## 5. What's already built that a greenfield plan would WRONGLY rebuild (FACT)

This is the table that argues against dropping a five-session greenfield plan on the tree.

| If a greenfield plan says "build…" | It already exists as | Verdict |
|---|---|---|
| a candidate-fact type / patch | `GraniteCandidateFact`, `GraniteCandidatePatch`, `GraniteGeneratedCandidatePatch` (`@Generable`) | **Reuse** |
| a deterministic-fact type | `DeterministicFact` (built, currently unused) | **Reuse + wire up** |
| an input packet for the model | `HotSeatPacket` + `HotSeatPacketBuilder` | **Reuse** |
| a schema/reconciliation validator | `GraniteSchemaValidator` + `GraniteValidationResult` | **Reuse + extend with apply** |
| a review/patch queue | `graniteReviewQueue` + `GraniteReviewItem` | **Reuse + persist + apply** |
| a deterministic reducer | `PatientStateEngine` + `ExtractorPass` (sole authority, value-typed) | **Reuse — do not touch** |
| an LLM backend abstraction | `TCCCLLMBackend` + 5 backends | **Reuse** |
| report/prose generators | Radio / ZMIST / Narrative / TranscriptCleaner | **Reuse** |
| a transcript evidence ledger | `TranscriptSegmentLedger` (transcript-only) | **Reuse + generalize (if event-sourcing adopted)** |
| the "LLM never writes state" rule | enforced today (return types + no apply path + `INSTRUCTIONS_FOR_AGENTS`) | **Preserve, make structural** |

---

## 6. Decisions this surfaces for the human (before any plan is written)

These are genuine forks; the answers determine whether the harness refactor is one focused sprint or several.

**Decision A — Is full event-sourcing actually wanted, or is "pure reducer + sole authority + candidate review queue" already the real target?**
The repo already has a deterministic, sole-authority reducer over value-typed state, plus a candidate/validate/queue boundary. A true immutable `EncounterEvent` log + replay is genuinely *new* infrastructure. If the underlying goal is "the LLM proposes, the deterministic engine disposes, and we can review/audit," much of that exists; event-sourcing proper (replayable log, persistence) is an additional, separable bet.

**Decision B — Build the candidate→state apply path?** (Recommended highest value.)
This is the one missing link that turns the existing hot-seat scaffolding from "validated and parked" into "operator-accepted facts become real state, safely, through the engine." It also forces the LLM-never-mutates invariant to be made *structural* rather than circumstantial.

**Decision C — Workflow engine: now or never-yet?**
Recommend deferring until A/B land; otherwise it is refactoring working glue for no behavior change.

**Decision D — Scope fence with Codex.**
The harness refactor must not touch audio ingestion (`AudioFrameLedger`, Granite Speech, chunked-encode) while Codex's Sprint 2 is in flight. Anything in §4 item 2 is theirs.

---

## 7. How this becomes per-sprint prompts (methodology fit)

The repo's pattern is: **design spec (`docs/superpowers/specs/`) → reconciliation / "what NOT to build" (`docs/specs/vN_*`-style) → per-task TDD plan (`docs/superpowers/plans/`) → machine board (`docs/granite/SPRINT_BOARD.yaml`) → acceptance gate (`SPRINT_*_ACCEPTANCE.md`)**.

This document is the design+reconciliation layer. The next step — once Decisions A–D are answered — is to write a per-task plan in `docs/superpowers/plans/` (TDD, with verification commands), scoped to the *gaps in §4*, explicitly reusing the §5 inventory, and fenced per Decision D. **Proposed slicing (RECOMMENDATION, not committed):**

- **Slice 1 (if Decision B = yes):** wire `DeterministicFact` emission from the engine into `HotSeatPacket`; build the accept→engine-mediated-merge apply path; make the LLM-never-mutates invariant structural. Tests-first against `GraniteHotSeatIntegrationTests`.
- **Slice 2 (if Decision B = yes):** operator review surface for `graniteReviewQueue` + conflict-resolution rules.
- **Slice 3 (only if Decision A = full event-sourcing):** generalize `TranscriptSegmentLedger` → `EncounterEvent` log + persistence; re-point the reducer at the log.
- **Slice 4 (only if Decision C = now):** thin deterministic workflow runner over the existing stages.

No slice touches the Codex audio lane.

---

## 8. Appendix — verification ledger

- All symbol citations in §§2–5 were confirmed present on disk by the adversarial verify pass; the single false citation (`DeterministicFact` standalone file) was removed.
- Status calls where the author diverges from the recon agents' uniform "partial": piece 4 (raised to *held/effectively built today* with a durability caveat) and piece 5 (lowered to *not-started as an engine*, stages-exist). All other calls match the verified agent output and the author's first-hand reads.
- Nothing in the repo was modified to produce this analysis.
