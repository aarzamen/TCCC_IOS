# Field interface and Yap Lab implementation plan

> For agentic workers: use superpowers:subagent-driven-development. Work on the assigned files; Codex coordinates integration and Git.

**Goal:** Deliver truthful clinical controls, an independent transcription lab, reproducible offline model setup and an interactive architecture explorer.

**Architecture:** Reuse ASR/LLM protocol implementations and their local model storage, while keeping clinical and lab records separate. Clinical edits go through engine events. Root navigation owns the three splash destinations.

**Tech stack:** Swift 6, SwiftUI, iOS 26, TCCCKit, FluidAudio 0.14.4, existing MLX shims, local HTML/JS explorer.

**Spec:** `docs/superpowers/specs/2026-09-09-interface-and-yap-lab-design.md`

## Global constraints

- Landscape iPhone UI; minimum action target 44 pt.
- No clinical state writes from language models or lab sessions.
- No automatic model downloads during inference.
- Preserve raw transcripts, existing encounters and model caches.
- Keep private recordings, diagnostics and weights out of Git.
- Retain splash with Clinical / DevTools / Yap Lab per latest request.

## Task 1 — Yap Lab (independent worker)

Files: new `TCCC_IOS/TranscriptionLab/*.swift`, `TCCC_IOSTests/YapLab*Tests.swift` only.
Interface: `YapLabView(state: AppState, onBack: @escaping () -> Void)`. Use existing `TranscriptStream` and `TCCCLLMBackend`; do not mutate state.engine or clinical transcript. Choose backend instances independently of clinical preferences.

- [x] Inspect existing adapters and benchmark file transcriber.
- [x] Implement persistent lab sessions, independent backend choices, live recording and local audio import, raw transcript view, separate prompt results, editable presets, cancellation and share.
- [x] Add regressions for text/session isolation, prompt construction and stale completion cancellation.
- [x] Report integration requirements and parser/test evidence to lead; no Git operations or shared Xcode project edits.

## Task 2 — Offline model resolver/preparation (independent worker)

Files: local model helper/backend loader files, new model readiness/preparation UI, build/staging scripts and focused asset tests. Do not edit AppState, SettingsOverlay, ContentView, project.yml or generated project; provide integration instructions.

- [x] Trace every offered model's loader, downloads, cache paths and local-directory inference.
- [x] Implement a shared inspectable local asset resolver including bundled and durable installed locations; fix Granite/MLX cache path mismatch and incomplete-cache readiness.
- [x] Build reusable offline preparation status view and an explicit build/install staging workflow without committing weights.
- [x] Research current primary model/Apple sources and document evidence-based pairing recommendation and redistribution limits.
- [x] Test missing/partial/valid model assets and ensure inference never silently falls through to a download.

## Task 3 — Interactive system map (independent worker)

Files: thread visualization directory `tccc-switchboard.html`, plus source/evidence in `reference/system-explorer/` if useful. No Swift edits.

- [x] Read actual architecture and visualize skill; author a playful responsive inline explorer using only local presentation logic.
- [x] Add subsystem inspection, synthetic spoken-example stepping, backend choices and meaningful failure toggles.
- [x] Validate interactions, narrow-width layout and factual source boundaries; label all simulations.

## Task 4 — Clinical UI repairs and integration (lead)

Files: AppState, clinical screens/components, root/splash navigation, new correction domain/app files, package/app tests, project.yml if required.

- [x] Replace misleading Edit/Review with an engine-backed correction path and editable operational 9-line fields; unknown values cannot count as confirmed.
- [x] Wire TQ/medication/vital actions to input and saved events, remove unsupported Photo/auto-export, persist markers and preferences.
- [x] Rename QR presentation and remove false transmit/AES claims; expose export errors and improve label legibility.
- [x] Fix Sender callback isolation and stale MEDEVAC model responses.
- [x] Wire Yap Lab and preparation into the existing app, regenerate Xcode project once workers finish.
- [ ] Complete repository publication and signed device build/update after the verified implementation.

## Execution ledger

Baseline source `2e1dec2` has current green package/simulator/CI evidence from the preceding sprint; reuse it without repeating unchanged tests. Plan review: Task 1 consumes existing adapters that Task 2 may change internally, so their public interfaces remain stable. Tasks 1/2 provide views; Task 4 alone edits navigation, Settings and AppState. Task 3 owns only visual files. No shared writer conflicts are planned. Native Claude is optional; this pass uses available side agents as explicitly authorized.


## Verification and review evidence (2026-09-09)

- Regression established before the 9-line repair: a GPS-only unassessed casualty
  incorrectly passed completion; nine assertions failed for invented entries.
- Integrated app suite: 242 executed, three expected skips, zero failures.
  Core package suite: 836 executed, zero failures. A later focused five-test
  clinical-entry pass validates the final observation snapshot repair.
- Asset helper: 14 native tests; packaging: five Python tests. Six real model
  packages, 5,749,589,446 bytes, pass native structural inspection and SHA checks
  both before and after embedding into a simulated app resource tree.
- Independent reviewers found and closed exact-form radio fallback leakage,
  manual-observation deduplication/carryover, stale draft context, delayed mic
  priming, unknown-field completion, source-selection errors, and cancellation
  evidence/model-teardown defects. Sender audio callback isolation is repaired.
- Simulator walkthrough: all three launcher choices; Yap Lab model/prompt controls;
  real Vitals save (synthetic pulse 92 appears in clinical state and Section C);
  9-line Add/Edit save (completion rises only for entered fields); truthful Handoff
  export cards. Visual follow-up reduces truncated titles and misleading read-only
  labels. No real casualty data is used by these tests.
- Explorer interactions and 320/360/736 layouts pass, in light and dark appearance,
  with zero browser errors. All animations/results are explicitly simulated.
- Signed iPhone build verifies all six embedded packages and passes strict/deep
  signature verification. The in-place device update preserves all 54 preexisting
  top-level Documents entries. Device auto-lock blocks remote launch verification.
- A normal Files import walkthrough reveals a Swift 6 executor assertion in the
  Apple Speech permission callback. A shared nonisolated, Sendable permission
  bridge fixes the cause; three regression tests cover background execution,
  duplicate callbacks and determined permission. All 30 selected speech/lab tests
  pass. Microphone callbacks receive the same explicit Sendable contract.
  Repeating the normal import no longer crashes: the simulator reports denied
  Speech permission, retains the audio/incomplete row, and reopens that saved
  session after app relaunch. Successful ASR remains a physical-device check.
- Physical-device model quality and matched pairing performance are not established
  by these source/UI checks.
