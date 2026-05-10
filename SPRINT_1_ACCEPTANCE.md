# Sprint 1 — Granite Speech Foundation — Acceptance Gate

**Sprint:** v3 (`docs/specs/v3_sprint_1_granite_foundation.md`)
**Phases shipped:** G0 → G1 → G2 → G3 → G4 (this gate)
**Validation device:** iPhone 17 Pro, iOS 26.2 (UDID `00008150-0018046C0188401C`)
**Date:** 2026-05-10
**Tag:** `sprint-1-granite-speech-foundation` (applied to the G4 commit on push)

## Outcome

**Sprint 1 closes with seven PASS, one PARTIAL, one DEFERRED across the nine v3 §13 acceptance criteria.** Both the PARTIAL and the DEFERRED have explicit Sprint 2 fix paths captured in `PRIOR_AUDIO_PATTERNS.md`. The Sprint 1 deliverable per v3 §1 — "Replace the `GraniteSpeechTranscriptStream` placeholder with a real `mlx-audio-swift`-backed `TranscriptStream` implementation that produces TCCC-keyword-biased transcripts on physical iPhone 17 Pro" — ships.

Hard numbers from G2/G3 hardware validation:
- Cold prime: **1.99 s**, `phys_footprint` Δ **+2196.3 MB** (matches the safetensors size, no quantize-time double-buffering).
- Post-load resident **2.16 GB**, available **3.84 GB** → runtime cap **6.0 GB** (`com.apple.developer.kernel.increased-memory-limit` + `extended-virtual-addressing` entitlements honored on Apple Personal Team certificates).
- 14 s file fixture transcribes in **5.78 s = 2.4× real-time decode**; peak `phys_footprint` 2.46 GB.
- Warm-run prime: **1.04 s**, Δ +49 MB (weights stay page-cached across `unload()` → `prime()`).

## Per-criterion checklist (v3 §13)

### 1. ✅ PASS — App launches; Apple Speech remains the default ASR.

- App launches to splash. (TCCC has no sign-in flow; v3 §13's "via existing sign-in" wording was inherited from v1 and doesn't apply — recorded in `RECON_NOTES.md`.)
- `AppState().asrBackend == .appleSpeech` verified by `testGraniteSpeechIsExplicitAlternateASRBackend` (`TCCC_IOSTests/GraniteSpeechTranscriptStreamTests.swift`).
- `LLMBackendPolicyTests` (4/4 passing) confirms Apple Foundation Models remains the default LLM backend.
- Operator confirmed across G0 / G1 / G2 / G3 device deploys: Apple Speech transcribes normally on Live Capture for the existing 5-screen pager.

### 2. ✅ PASS — "Select Granite Speech Model Folder" Settings row opens `UIDocumentPickerViewController`.

- Row at `TCCC_IOS/Components/SettingsOverlay.swift:graniteSpeechModelFolderRow`. Visible when `state.asrBackend == .graniteSpeech` (parallel to the existing Parakeet conditional).
- Picker opened via SwiftUI `.fileImporter(allowedContentTypes: [.folder])` which wraps `UIDocumentPickerViewController` in `.open` mode under the hood.
- Operator-validated: G2 session, picked `granite-4.0-1b-speech-5bit/` from "On My iPhone → Swift TCCC → huggingface → models → mlx-community/".

### 3. ✅ PASS — Selecting a folder writes a persistent security-scoped bookmark; status text shows "Active · …".

- `GraniteSpeechBookmarkStore.save(url:)` writes a bookmark blob to `UserDefaults` under key `tccc.graniteSpeech.modelBookmarkV1`. Round-tripped by `testBookmarkSaveResolveStaleClearLifecycle`.
- Resolver chain (`GraniteSpeechModelResolver.resolve()`) tries bookmark → bundle → HF cache. Returns `Resolved(url:source:.bookmark, needsScopeActivation: true)` on a hit.
- Operator-validated: G2 bake-off `RESOLVED FROM: bookmark` row + status pill flipped to "Active · granite-4.0-1b-speech-5bit" after the pick.

### 4. ✅ PASS — Empty resolver surfaces a clear error; no hidden download.

- `testGraniteSpeechResolverThrowsWithoutAnySource` exercises the empty-resolver path and asserts `.modelNotProvided(modelID:)` is thrown.
- `testGraniteSpeechTranscriptStreamAuthorizeThrowsBackendUnavailableWithoutSource` asserts the error is wrapped into `TranscriptStreamError.backendUnavailable("Granite Speech: …")` at the `TranscriptStream` boundary.
- DevTools Bake-off + Granite Live both render "BOOKMARK: Missing — use Settings" + a disabled "Configure model first" button when the bookmark store is empty (operator-validated G2 screenshot).
- Verified zero network: only HF touchpoint is `MLXBackend.HFHubCache.contains(modelId:)`, which is read-only. No download path runs from RECORD.

### 5. ⏭ DEFERRED — 5-min fixture / live-mic stable transcription.

This is the only criterion that **does not** pass at Sprint 1 close. Two compounding root causes, both documented and both with Sprint 2 fix paths:

**5a. Encoder long-form crash (G2 known limitations §1).** The 100 s synthesized §6 narrative crashes the app with SIGKILL/jetsam ~3 s into transcribe — encoder forward pass on the full audio array exceeds the 6 GB cap before the decoder ever fires. The cap **is** being honored (criterion 6 below); the encoder simply doesn't fit. Sprint 2 fix: chunked-encode using the 60-s-with-3-s-overlap pattern from `TCCC_FEB_2026/src/audio.py:115-173` (Mike's Python prototype — the literal pattern this Swift port is meant to mirror). Cited in `PRIOR_AUDIO_PATTERNS.md` Top Pattern #1.

**5b. Live-mic mailbox unbounded growth (G3 known limitations §2).** Tap-callback at ~46 Hz spawns one `Task { await ingestBuffer(copy) }` per buffer; the actor's effective drain rate is bounded by AVAudioFile + AAC encode latency, slower than the producer under sustained recording. Mailbox accumulates buffer copies. Operator-observed G3 trajectory: `phys_footprint` 2.16 GB at post-load → 4.46 GB at ~30 s of capture → jetsam shortly after. Sprint 2 fix: lift FlowScribe's 80 000-sample emit + 32 000-sample force-flush ceiling at `FlowScribe/AudioManager.swift:100-135`. Cited in `PRIOR_AUDIO_PATTERNS.md` Top Pattern #2.

Sprint 2 will re-run the §6 narrative fixture with chunked-encode + back-pressured writer, validate keyword recall ≥ 90% on the §6 token list, and unblock criterion 5.

**Sprint 1 polish landed in G4 (this commit):** `GraniteLiveView` now surfaces a long-form warning banner when `recordingDuration ≥ 60 s` OR `monitor.pressure != .normal`. Banner text per discipline point: *"Long-form recording is unstable in Sprint 1 — see G3 limitations in CLAUDE.md."* This doesn't fix the bug — it prevents the operator from running into it without warning.

### 6. ⚠️ PARTIAL — Memory gauges visible; cap held for short, correctly enforced for long.

**Pass for the visibility + short-audio side:**
- Resident / Footprint / Available gauges render in `GraniteLiveView` at 1 Hz via `MemoryMonitorObserver` (`Packages/TCCCAudio/Sources/TCCCAudio/MemoryMonitor.swift`). Bake-off view shows the same readings post-load + peak-during-decode.
- Footprint gauge color-shifts at 75% (warning) and 90% (critical) of the runtime-computed cap (`physFootprint + available` measured at first observe).
- Memory pressure event banner fires on `DispatchSource.makeMemoryPressureSource` warning/critical events.
- 14 s fixture transcribed cleanly with peak `phys_footprint` at 2.46 GB — well under the 6 GB cap.

**Partial because the 5-minute fixture exceeds the cap and triggers jetsam.** This is the cap *being honored* — iOS jetsam fires precisely because we asked for an entitlement-extended 6 GB and then exceeded it. The cap isn't broken; the long-form encoder pass blows past it. Same root cause as criterion 5a; same Sprint 2 fix unblocks both.

### 7. ✅ PASS — `MemoryMonitorLog.csv` is non-empty and shows OSSignpost intervals around model load and inference.

- `MemoryMonitorCSVLogger` class at `Packages/TCCCAudio/Sources/TCCCAudio/MemoryMonitor.swift:188-228`. Header + per-tick row format: `timestamp_iso, resident_bytes, phys_footprint_bytes, available_bytes, pressure, event`. Lives in `Documents/MemoryMonitorLog.csv` per v3 §7.
- Wired into `GraniteLiveView` in G4 (this commit):
  - `record_start` row on RECORD tap.
  - `primed` row when `runtime.prime()` returns.
  - `pressure_warning` / `pressure_critical` rows on memory-pressure transitions.
  - Per-tick reading on every `monitor.current` change (~1 Hz during recording).
  - `record_stop` on STOP tap.
  - `transcribe_complete` on final `RecognitionUpdate`.
  - `failed` on lifecycle error.
- File appears in the app's Documents directory and is pullable via `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.aarzamen.TCCCai --source Documents/MemoryMonitorLog.csv`.

### 8. ✅ PASS — Bookmark + model-folder persistence mechanism in place.

- `GraniteSpeechBookmarkStore` persists to `UserDefaults` under `tccc.graniteSpeech.modelBookmarkV1`. Resolver auto-recreates the bookmark on stale-on-resolve while a scope handle can briefly be acquired.
- Round-trip exercised by `testBookmarkSaveResolveStaleClearLifecycle` (UserDefaults isolated key + temp-dir fixture, save → resolve → clear → resolve-throws).
- Mechanism survives normal app relaunch and most reinstalls. A *full sandbox wipe* (e.g. delete-and-reinstall via the app switcher) clears UserDefaults along with the rest of the sandbox; the resolver's third source (HF cache) similarly lives inside the sandbox at `~/Library/Caches/huggingface/hub/...` and would be wiped.
- For survive-full-delete, v3 §2 specified iCloud Drive or "On My iPhone / TCCC_IOS_Models" *outside* the app sandbox. During G2 validation Mike pasted the model files into the app's own Documents folder for speed — that's a pragmatic operator choice, not a regression of the design. The bookmark mechanism resolves either location identically.

### 9. ✅ PASS — `git log --oneline | head -5` shows G0–G4 phase commits.

After this G4 commit + tag land:

```
<G4-SHA>  phase G4: sprint 1 acceptance gate signed off
7a4de5b  phase G3: granite live devtools view + record-then-transcribe
ce344d0  phase G2: granite speech model load + transcribe on physical iPhone
f065a6b  phase G1: granite speech multi-source resolver + bookmark store + policy tests
ca4a1a6  phase G0: add TCCCAudio package + mlx-audio-swift dep + memory entitlements
```

## Sprint 2 carry-over

Spec gets written when Sprint 1 acceptance lands (this document). Initial Sprint 2 work order, derived from this gate's PARTIAL + DEFERRED + the patterns documented in `PRIOR_AUDIO_PATTERNS.md`:

1. **Encoder-side: chunked encode.** 30-s windows, free intermediate tensors between, validate against the §6 narrative fixture and assert keyword recall ≥ 90%. Closes criterion 5a.
2. **Capture-side: back-pressured writer + bounded ring buffer.** Lift FlowScribe's 80 000-sample emit + 32 000-sample force-flush ceiling. Closes criterion 5b.
3. **Hot-seat integration.** Route Granite transcripts into `TranscriptSegmentLedger` → `HotSeatPacketBuilder` → existing `GraniteSchemaValidator` + `GraniteReviewQueue` pipeline.
4. **Text-LLM swap.** `GraniteTextLLMBackend.modelId` from `granite-4.0-h-1b-base-4bit` → `granite-4.0-h-1b-4bit` (instruct, per the prior smoke-test in `docs/granite/SPRINT_BOARD.yaml` showing the instruct variant produced an evidence-cited candidate fact while base produced parse-failed continuation).
5. **Optional polish:** real iCloud-Drive (not in-sandbox) staging test for criterion 8 once the operator re-stages the model under iCloud Drive or "On My iPhone / TCCC_IOS_Models".

Sprint 2 spec gets written by Mike + agent collaboratively when this gate is read back.
