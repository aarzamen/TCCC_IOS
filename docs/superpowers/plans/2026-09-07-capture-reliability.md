# Capture reliability implementation plan

> **Current authority (2026-09-08):** Follow PROJECT_POLICY.md. GPT-6 owns planning, architecture, implementation decisions, verification and integration. Codex may implement directly or delegate bounded code/tests; native Claude is optional. Use superpowers:subagent-driven-development when delegating. Each task establishes regression evidence before its fix.

**Goal:** Stop fabricated export defaults and close verified Apple Speech completion/lifecycle losses.

**Architecture:** Preserve existing backend and engine boundaries. Make recognition completion and request identity explicit; retain partial evidence without pretending it is complete. Unknown identity fields remain blank through the existing deterministic mapper.

**Tech Stack:** Swift 6, TCCCKit, SwiftUI, Speech, AVFoundation, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-07-capture-reliability-design.md`

## Global constraints

- iOS 26.0 current project minimum; offline recognition remains required.
- No new dependencies, model downloads, backend-default flips, remote inference, or patient data in worker prompts.
- All patient-state mutations retain the engine/event-log route.
- Unknown does not mean NKDA; explicit input must survive mapping.
- Develop in this isolated branch. Commits, pushes, main integration and repository publication are authorized; integrate validated changes without renewed approval. Preserve device data.

### Task 1: Honest identity defaults

Files: `TCCC_IOS/App/AppState.swift`, `TCCC_IOSTests/DD1380WiringTests.swift`; inspect `TCCC_IOS/App/AppState+Lifecycle.swift` if present and the actual lifecycle implementation before adding a file to scope.

Consumes: `AppState.makeDD1380Card() -> DD1380CardData?`.
Produces: same API, blank unknown identity values with explicit-value preservation.

- [ ] Native Claude writes tests first: fresh encounter card name/unit/last4/battle-roster/allergies must equal `""`; explicitly supplied name `"SMITH, A."`, unit `"TEST UNIT"`, service suffix `"1234"`, and allergies `"PENICILLIN"` map verbatim. Explicit `"NKDA"` remains `"NKDA"`. Extracted PDF text from a fresh card contains none of the old fabricated header values. Lifecycle transitions do not carry prior casualty identity.
- [ ] Codex runs `xcodebuild test ... -only-testing:TCCC_IOSTests/DD1380WiringTests` and records the expected failures against unchanged production.
- [ ] Native Claude removes fabricated defaults and implements the smallest necessary lifecycle reset, using the existing blank-field mapper/renderer contract.
- [ ] Codex repeats focused tests, performs source review and commits the bounded fix.

### Task 2: Truthful benchmark completion

Files: `TCCC_IOS/DevTools/TranscriptionBenchmark/AppleSpeechFileTranscriber.swift`, `TranscriptionBenchmarkView.swift`, benchmark result schema where defined, and a focused app test file. An internal pure state helper may be added alongside the adapter if it is consumed by production callbacks.

Consumes: recognizer text/final/error callbacks and timeout/cancellation.
Produces: `AppleSpeechFileTranscriber.Output` with transcript plus explicit termination metadata; benchmark JSON/summary expose that metadata instead of discarding failures.

- [ ] Native Claude first writes deterministic tests covering partial→timeout, partial→error, final→cancelled timeout, cancellation, overlapping requests, and stale callbacks. Expected outcomes retain partial text but never report timeout/error as finalized.
- [ ] Codex runs the focused tests and records failure before production changes.
- [ ] Native Claude implements single-completion, run-scoped callbacks and cancelled-timer handling; benchmark output records termination, evidence, and warnings. A final callback indicates recognizer finalization only, not whole-file coverage.
- [ ] Codex verifies JSON/summary behavior and focused tests; review and commit.

### Task 3: Live-capture lifecycle

Files: `TCCC_IOS/Audio/SpeechRecognizer.swift`, narrowly scoped production lifecycle helper if needed, `TranscriptStream.swift`/app capture consumer only if an existing status path is insufficient, and focused lifecycle tests.

Consumes: start, audio buffers, recognizer callbacks, force-finalize, stop/tail, and abort.
Produces: ordered, capture/request-scoped recognition updates with no stale callback crossing a capture boundary.

- [ ] Use the independent read-only audit to identify concrete failing sequences. Record the exact ruling and selected seams in the sprint ledger before worker implementation.
- [ ] Native Claude writes regressions: old request callback cannot terminate a new request; final text precedes rollover; request shutdown retains intervening audio; stop honors its configured tail; tail expiry permits final drainage; abort cancels promptly without later mutation.
- [ ] Codex runs regressions red, then dispatches the minimal native-Claude fix. Preserve existing provisional transcript identity semantics and protected audio capture.
- [ ] Run focused and full app tests; independent concurrency/source review; commit only after findings are closed.

### Task 4: Device evidence and closeout

- [ ] Preserve existing device encounter data before test installation. Reuse authored benchmark fixtures; never send private recordings to Claude.
- [ ] Run the benchmark on the available iPhone, compare callback coverage/completion evidence with the historical result, and retain explicit incomplete outcomes. Exercise the live path when device/audio control permits; otherwise label that validation incomplete.
- [ ] Run the full package and app gates after final changes; record actual test counts and model-gated skips.
- [ ] Whole-branch independent review; reconcile findings; record exact source commit, device evidence and remaining acoustic limitations. Commit, push and integrate validated changes under the standing publication authorization.

## Execution checkpoint — 2026-09-07

Worktree: `codex/ios-capture-reliability`, based on `5edde13`. Production implementation is pending; no sprint commits or phone installation yet.

| Gate | Verified result |
|---|---|
| Unchanged TCCCKit baseline | 793 tests pass, zero failures |
| Unchanged app baseline | 103 passed, 11 failed, 2 skipped; 116 total |
| Microphone failure recheck | Passes after granting simulator microphone permission; ten persistence failures remain |
| Identity regressions | Fail at runtime on fresh card/PDF mock defaults and identity retained by NEW/WIPE |
| Benchmark regressions | Fail to compile because the proposed production state helper is absent |
| Device preservation | Existing encounters and authored benchmark material copied and checksummed before any installation |
| Native worker | Two tests-only jobs completed; capture test job stopped because Claude subscription authentication is signed out |

The persistence prerequisite is a narrow repair to `ProtectedWrite`: use the file-attribute setter while retaining complete file protection and propagated errors. Independent review and focused persistence tests must verify that repair. Do not suppress the baseline failures or weaken protection.

At the September 7 checkpoint, native Claude login was pending. Authentication was verified working on September 8. Worker prompts, exact red-test logs, audit and continuation ledger are preserved under `.superpowers/sdd/2026-09-07-capture-reliability/`. Under the updated policy, Codex chooses the implementer and owns continuation regardless of any worker's availability. References to native Claude in the task checklists describe the original assignment, not an exclusive implementation requirement.
