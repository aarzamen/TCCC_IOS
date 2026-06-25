# Reconciliation Apply Path — Design Spec

**Date:** 2026-06-24
**Status:** Approved design (brainstorming complete) → next step: implementation plan via writing-plans
**Repo state:** `main` @ `87a17eb`, 724 TCCCKit tests green
**Derives from:** `docs/superpowers/specs/2026-06-24-harness-reconciliation.md` (the recon that mapped the GPT event-sourced harness onto the repo) and `docs/granite/GRANITE_HOT_SEAT_ARCHETYPE.md` (the safety contract).

---

## 1. Decisions this spec encodes

From the harness reconciliation (§6 of that doc), the human decided:

- **A = yes** — full event-sourcing is the eventual target (immutable `EncounterEvent` log + replay).
- **Durability = retained archive** — encounters are persisted, encrypted, and **kept** on device across casualties (not wiped on new-casualty).
- **B = yes** — build the candidate→state apply path.
- **C = defer** — no deterministic workflow engine this cycle.
- **D = correct** — the audio-ingestion lane (Granite Speech, `AudioFrameLedger`, chunked-encode) is Codex's; out of scope until its Sprint 2 signs off in `docs/granite/SPRINT_BOARD.yaml`.
- **Sequencing = visible-value-first** — build the apply path on the **current string-driven engine** now; retrofit the `EncounterEvent` log + durable retained archive in a **separate later spec/plan cycle**. The apply path will be refactored onto the event spine then; some rework is knowingly accepted.

**Therefore this spec scopes ONE deliverable: the operator-mediated reconciliation apply path on the current engine.** Event-sourcing and the durable archive are documented here as the committed north star (§7) but are **not built in the plan that derives from this spec.**

## 2. Problem this solves (the gap)

The hot-seat pipeline already builds candidates, validates them, and parks them: `GraniteHotSeatGenerator` → `GraniteSchemaValidator.validate` → `applyGraniteCandidatePatchForReview` appends a `GraniteReviewItem` to `graniteReviewQueue`. The chain **stops there** — `GraniteReviewQueue.swift:60` only validates + queues, and `testValidPatchIsQueuedForOperatorReviewWithoutMutatingState` asserts state is unchanged. Two further facts: `deterministicFacts: []` is hardcoded empty into the packet (`GraniteReviewQueue.swift:35`), and there is no operator surface for the queue.

This spec closes that: an operator reviews queued candidates and accepts/rejects them; accepted facts become real `PatientState` mutations **through the deterministic engine**, never through the LLM.

## 3. Architecture — five components

### ① DeterministicFact projector — `PatientState → [DeterministicFact]`

A pure projector maps the engine's current `PatientState` into `[DeterministicFact]` (`DeterministicFact` exists at `HotSeatPacket.swift:25` with `{id, patientId, domain, field, value, evidenceIds, extractor, confidence}`), passed into `HotSeatPacketBuilder.build(deterministicFacts:)` in place of today's `[]`. This gives the LLM the engine's ground truth as context so it can challenge or avoid duplicating it.

Evidence linkage is **best-effort this cycle** (see §7 debt). Confidence for deterministic facts is `.high`; `extractor` names the producing pass where derivable, else a generic tag.

### ② The apply path + field-router — **the structural invariant**

A new **engine-mediated** apply path is the only route from an LLM-originated candidate to state:

```
validated patch → GraniteValidationResult.acceptedFacts
              → operator explicitly accepts a fact
              → OperatorAcceptedFact (constructible ONLY from a validated+accepted fact)
              → PatientStateEngine.apply(acceptedFacts:)   // actor method; engine stays sole authority
              → FieldRouter maps (domain, field) → typed PatientState setter
              → state refresh via the existing engine.snapshot() / refreshPatientSnapshot() path
```

- The router's `(domain, field) → setter` table is **bounded by the rubric already in the repo**: `reference/rubric/extracted/dd1380_field_inventory.json` + `reference/rubric/extracted/march_paws_vocabulary_2026.json`. The same files `RubricDriftProtectionTests` already loads.
- `apply(acceptedFacts:)` accepts only `OperatorAcceptedFact` values. That type **cannot be constructed from raw LLM text** — only from a fact that is a member of a `GraniteValidationResult.acceptedFacts` set plus an explicit operator-accept action. This is what makes "LLM-never-mutates-state" *structural* rather than conventional: there is no compile-reachable path from model output to a `PatientState` setter that bypasses validation + operator acceptance + rubric routing.

#### Acceptance gate for ② — the boundary gate (both directions)

The gate proves the router enforces the boundary in **both** directions: it keeps bad facts OUT **and** lets good facts THROUGH. A router that rejects everything is secure and useless and must NOT pass the gate. This is a **family** of tests, and **all of it green is the acceptance gate for shipping ②**.

**Rejections (bad facts stay out)** — each must **reject explicitly**:

1. **unknown domain** → rejected
2. **known domain, unknown field** → rejected
3. **known `(domain, field)`, value outside the rubric's allowed range/enumeration** → rejected
4. **well-formed fact whose `(domain, field)` pair has no setter wired yet** → rejected

**Acceptance (good facts go through)** — the fifth, positive member:

5. a well-formed fact whose `(domain, field)` **IS** wired and whose value **IS** in rubric range → the setter **fires** and `PatientState` mutates **through the engine** (asserted via `engine.snapshot()`).

Each rejection must return a typed reason surfaced to the operator and logged via `appendSystem`. **Never silently drop. Never best-effort coerce.** If any rejection can leak a mutation, *or* case 5 fails to mutate, the field-router invariant is theater. ② does not ship until the full family — four rejections **plus** the positive case — is green.

### ③ Operator review surface

A new review view, reachable from Live Capture and/or the TCCC Card, lists `graniteReviewQueue` items (`GraniteReviewItem { patch, validation, status }`). For each candidate fact it shows the value, its cited evidence, and confidence, with per-fact **Accept** / **Reject**.

- Gloved-hand constraints (hard constraint #4): hit targets ≥ 44 pt, primary actions 56–64 pt.
- **Reject is destructive** → long-press with visual progress fill (per constraint #4), consistent with existing `HoldToConfirmButton` usage.
- **Accept** → routes through ②. State refreshes through the normal snapshot path; no direct view-to-`PatientState` write.

### ④ Conflicts + the deferred-conflict resting state

`GraniteValidationResult` already emits `conflicts` (LLM value vs. existing engine value). The review surface renders a conflict and forces an operator choice; it **never auto-resolves**. Recency/correction phrases are advisory hints only.

**Resting state (defined):** a conflict the operator **neither accepts nor rejects stays in the queue**, and the casualty card displays the **existing deterministic engine value, unchanged**, until the operator actively overrides it. The existing value is the safe default and holds. "Held" is therefore never an ambiguous or blank state — it is "engine value still shown, override pending."

### ⑤ Lifecycle / WIPE boundary (matched pair)

The durable retained archive (built in the deferred cycle, §7) changes the meaning of the two lifecycle actions, which become **opposite**:

- **new-casualty / end-care** → **preserves** the active encounter (archives it, encrypted) and starts fresh. Accidental data loss ends.
- **WIPE (HOLD 3s)** → **hard-purges the entire archive**. Deliberate OPSEC sanitization. Stays a held confirmation.

These are a matched pair, not a contradiction: retention removes *accidental* loss; WIPE preserves *deliberate* total erasure.

**UI requirement (stated, not an implementation detail):** because new-casualty and WIPE will have **opposite consequences** once records are durable, they MUST be **unmistakably distinct** in the UI so a gloved operator under stress can never fat-finger one for the other:

- different affordance — WIPE keeps the HOLD-3s long-press; new-casualty must not look or feel like it;
- ideally a **different screen region**;
- distinct labeling/coloring consistent with the theme system.

**Phasing of this requirement:** in this visible-value-first cycle the archive is not yet built, so new-casualty retains today's behavior. But the distinctness affordance is established **now** (alongside the review-UI work) so it is already in place before the semantics diverge in the deferred cycle — the dangerous window (opposite consequences, similar affordances) must never exist.

## 4. Data flow (end to end, this cycle)

```
transcript (current string-driven path, unchanged)
  → PatientStateEngine.processTranscript            [existing, untouched]
  → PatientState                                     [existing projection]
  → DeterministicFact projector  ①                   [NEW]
  → HotSeatPacketBuilder.build(deterministicFacts:)  [now non-empty]
  → GraniteHotSeatGenerator.candidatePatch           [existing]
  → GraniteSchemaValidator.validate                  [existing]
  → graniteReviewQueue (GraniteReviewItem)           [existing]
  → Operator review surface  ③                        [NEW]
       Accept → OperatorAcceptedFact → PatientStateEngine.apply(acceptedFacts:) → FieldRouter  ②  [NEW]
       Reject → discard, log
       Conflict untouched → engine value holds  ④
  → engine.snapshot() / refreshPatientSnapshot       [existing refresh path]
```

The engine remains the **sole writer** of `PatientState`; the new `apply(acceptedFacts:)` is an engine method, so that property is preserved.

## 5. Testing strategy

TDD, mirroring `GraniteHotSeatIntegrationTests`. New tests:

- **The boundary gate (§3 ②), both directions** — the four rejection cases (each explicit reject with a reason and **zero** state mutation) **plus** the positive case (well-formed, wired, in-range fact → setter fires and state mutates through the engine via `engine.snapshot()`). A reject-everything router must fail this gate. Full family green is the acceptance gate for ②.
- accept → `PatientState` mutates, and the mutation is observable through `engine.snapshot()` (proving it went through the engine).
- reject → no mutation.
- conflict left untouched → card still shows the prior engine value (④ resting state).
- a model candidate that **contradicts** a projected deterministic fact (①) routes to the **conflict path** (④) — never the accept path, never a silent drop — and the contradiction is operator-visible. Feeding deterministic facts in exists precisely to let the model challenge them; a challenge must land somewhere visible, auto-resolved in neither direction.
- `OperatorAcceptedFact` cannot be constructed from an un-validated/un-accepted fact (structural-invariant test).
- packet `deterministicFacts` is now non-empty for a populated `PatientState` (①).
- all **724** existing TCCCKit tests remain green.

**Implementation-time verification (a build-phase check, not a design requirement):** when confirming the 724 tests stay green, check that **none asserts the old destructive new-casualty behavior as correct**. If one does, it is the parity-test situation again — it gets **corrected, not satisfied**, because green-on-that-test would mean preserving the data-loss behavior this work exists to fix. Flag it if found.

## 6. Scope fence

This cycle touches: the `Intelligence/` hot-seat files, a new `FieldRouter` / apply method on `PatientStateEngine` (TCCCKit), a new review view, and lifecycle-affordance differentiation. It does **not** touch: audio ingestion, `TranscriptStream`/Granite Speech, `AudioFrameLedger`, or anything in Codex's `codex/sprint-2-audio-research` lane. It does **not** build the event log or the durable archive.

## 7. Deferred — the committed north star (own later spec/plan cycle)

Recorded so it can't be lost, **not built here**:

- `EncounterEvent` type + immutable append-only `EncounterLog` as canonical memory; reducer re-pointed to fold the log; replay-on-relaunch.
- **Durable, encrypted (`NSFileProtectionComplete`), retained per-casualty archive** + the WIPE-purges-archive / new-casualty-preserves semantics of §3 ⑤.
- Refactor of the §3 ② apply path to emit an `EncounterEvent` (e.g. `.factAccepted`) that the reducer folds, replacing the direct mutation built this cycle.
- Deterministic workflow engine (C, deferred further).

**Evidence-linkage debt (named + gated):** the best-effort evidence linkage on deterministic facts (§3 ①) is a deliberate stopgap for this cycle; its replacement is **gated on the `EncounterEvent` log** — when the ledger lands, the apply path's evidence handling is **re-derived from events, not patched onto the current code**. This is named explicitly so it cannot calcify into a provenance story that was never actually built.

## 8. Open interface sketches (for writing-plans to harden)

- `func project(_ state: PatientState) -> [DeterministicFact]` — the ① projector.
- `struct OperatorAcceptedFact` — opaque wrapper constructible only via `init?(_ fact: GraniteCandidateFact, acceptedFrom: GraniteValidationResult)` that returns nil unless the fact is in `acceptedFrom.acceptedFacts`.
- `extension PatientStateEngine { func apply(acceptedFacts: [OperatorAcceptedFact]) -> [FieldRouteRejection] }` — returns the (possibly empty) list of explicit rejections; mutations land in the actor's `patients`.
- `enum FieldRouteRejection { case unknownDomain / unknownField / valueOutOfRubricRange / noSetterWired }` — the four §3 ② cases, surfaced + logged.
- `FieldRouter` — rubric-bounded `(domain, field) → setter` table; the only place that knows how to write a `PatientState` field from a routed fact.
