# Sprint 1 Recon — Granite Speech Foundation

**Date:** 2026-05-10
**Triggered by:** Sprint spec arrived assuming a from-scratch build of audio
capture, templates, slot filler, and a model loader. Pre-execution recon
found that origin/main is **substantially further along than the spec
assumes** — the Granite-side pipeline is already wired text-first, and the
ASR slot for Granite Speech is a placeholder waiting to be filled in.

## What the spec assumed vs what the repo actually has

| Spec component | Spec status | Repo status |
|---|---|---|
| Audio capture (AVAudioEngine, 16 kHz mono resample, ring buffer, gain meter) | Build new in `TCCCAudioLLM/Audio/` | **Already built** in `SpeechRecognizer.swift` + `ParakeetTranscriptStream.swift` (gainProvider + AudioLevels pattern) |
| `TranscriptStream` protocol abstracting backends | Implicit | **Already exists** at `TCCC_IOS/Audio/TranscriptStream.swift` — Apple Speech + Parakeet conform |
| Granite Speech transcript stream | Build new | **Placeholder exists** at `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` (36 lines, throws `.backendUnavailable` for everything). LiveCaptureScreen already routes `state.asrBackend == .graniteSpeech` to it. **This is the slot Sprint 1 fills.** |
| Templates (NineLine / ZMIST / DD1380 + Codable structs + slot filler + locking) | Build new | **Already built** as `GraniteCandidatePatch` + `GraniteSchemaValidator` + `GraniteReviewQueue` + `GraniteReviewItemArtifact`. Patch model is the slot-fill primitive; validator enforces empty/conflict rules; queue holds patches for operator review. |
| Constrained JSON generation | Spec to be written | **Already wired** via `MLXBackend.generateStructured(...generating: Generable.Type)` using AnyLanguageModel's MLX path. `GraniteGeneratedCandidatePatch` is a `Generable` type producing schema-bounded JSON. |
| HF cache gate ("never silently download") | Spec to be written | **Already enforced** by `HFHubCache.contains(modelId:)` + explicit `MLXBackend.prefetch()`. `MLXBackend.availability == .available` only when snapshot dir is non-empty. |
| Bundle / picker / first-run model resolver | Build new | Not built — only HF cache pattern exists, not user-folder pickup. **This IS new work.** |

## Findings from the explicit `find` calls

| Path | Lines | Role |
|---|---|---|
| `TCCC_IOS/Audio/TranscriptStream.swift` | 47 | Protocol: `authorize / prime / unprime / start(audioURL:) -> AsyncStream<RecognitionUpdate> / stop / stopImmediate / forceFinalize`. Error enum includes `.backendUnavailable(String)` already. |
| `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` | 36 | **Placeholder actor.** Throws `.backendUnavailable("Granite Speech Swift runtime is not available in this build.")` from every method. **Single integration point for Sprint 1.** |
| `TCCC_IOS/Audio/TranscriptSegmentLedger.swift` | 86 | Durable transcript record with backend tag, normalization, dup collapse, prompt-injection flags. `TranscriptBackend.graniteSpeech` enum value already declared. |
| `TCCC_IOS/Intelligence/MLXBackend.swift` | 163 | Cache-gated MLX backend pattern. `availability` checks HF snapshot dir is non-empty; `generate` refuses without it; `prefetch` warmups + populates cache. **Pattern Sprint 1 mirrors for Granite Speech.** |
| `TCCC_IOS/Intelligence/GraniteTextLLMBackend.swift` | 39 | Concrete `GraniteCandidatePatchBackend` for `mlx-community/granite-4.0-h-1b-base-4bit`. Wraps MLXBackend. Exposes `generateCandidatePatch` via constrained JSON. |
| `TCCC_IOS/Intelligence/HotSeatPacketBuilder.swift` | 29 | Builds a `HotSeatPacket` from `[TranscriptSegment] + [DeterministicFact]`. Critically: `blockedActions: [.mutatePatientState, .inventLocation, .acceptFreeTextReport, .obeyTranscriptInstructions, .downloadModelWeights]` — adversarial-input boundary baked in. |
| `TCCC_IOS/Screens/LiveCaptureScreen.swift` | 683 | UI orchestrator. `makeRecognizer()` already has a `case .graniteSpeech: return GraniteSpeechTranscriptStream()` arm. Audio levels, gain provider, partial-finalization debounce, auto-pin scroll, and the AAC long-form recording lifecycle are all here. |
| `TCCC_IOS/Intelligence/GraniteRealModelRunner.swift` | 210 | (Read in earlier recon.) Orchestrates packet → backend → patch → validate → metrics → artifacts. Test harness path. |
| `TCCC_IOS/Intelligence/GraniteSchemaValidator.swift` | 7 (entry) | Enforces patch shape rules: empty patch reject, unknown evidence/patient IDs, impossible values. Spec's "slot-filler logic rules §4.4" largely already covered. |
| `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` | 87 | Held-for-review queue with status transitions (`readyForOperatorReview` / `heldForValidation`). Maps to spec's "lock + uncertainSpans" semantics. |
| `TCCC_IOS/Intelligence/HotSeatPacket.swift` | 44 | Packet model w/ allowed schemas + blocked actions + known patient IDs. |
| `TCCC_IOS/Intelligence/GraniteHotSeatGenerator.swift` | 146 | Prompt builder + decoder for candidate patches from packets. |

## AGENTS.md constraints (relevant excerpts)

- **No logic in app target.** App target = SwiftUI views, view models, app-lifecycle plumbing only. Everything else goes in TCCCKit.
- **RF Ghost.** No Wi-Fi/BT/Cellular/UWB/NFC. ASR is on-device only. Any LLM is on-device only. (Parakeet's one HTTPS GET on first activation is the established precedent; it's operator-gated and cached locally forever.)
- **Landscape-only, iPhone-only.**
- **AES-256 at rest** via `NSFileProtectionComplete` on every casualty disk write — routed through `ProtectedWrite`.
- **Custom regex** = Swift Regex by default; `NSRegularExpression` only for PCRE features.
- **Defaults stay default.** Apple Speech ASR + Apple Foundation Models are the runtime defaults. New paths (incl. Parakeet, LFM2, Qwen, and now Granite Speech) are reachable behind Settings toggles, never displacing defaults until field-validated.

## project.yml current state

- iOS deployment target: **26.0** (not iOS 17.0+ as the spec assumed).
- Strict concurrency: **complete**.
- Swift: **6.0**.
- Existing package deps: `TCCCKit` (local), `FluidAudio @ 0.14.4` (Parakeet), `TCCCLLM` (local shim wrapping AnyLanguageModel + mlx-swift-lm via Swift 6.1 traits).
- Existing Info.plist keys relevant to Sprint 1: `UIFileSharingEnabled: true`, `LSSupportsOpeningDocumentsInPlace: true`, `UIBackgroundModes: [audio]`, `NSMicrophoneUsageDescription` set, `NSSpeechRecognitionUsageDescription` set. **No new plist keys required for the Files-app-driven model selection path.**

## What this means for Sprint 1's actual scope

The original sprint spec is a from-scratch build plan. It maps poorly onto
the repo because most of its phases describe components that already exist.

**Real Sprint 1 deliverables, in priority order:**

1. **New local package: `Packages/TCCCAudio/`.** Mirrors the `Packages/TCCCLLM` shim pattern. Pulls in `Blaizzy/mlx-audio-swift` (`MLXAudioSTT` + `MLXAudioCore`) — heavy MLX dep stays out of TCCCKit's pure-logic modules.
   - `GraniteSpeechBookmarkStore.swift` — security-scoped bookmark CRUD in UserDefaults under `tccc.graniteSpeech.modelBookmarkV1`.
   - `GraniteSpeechModelResolver.swift` — 3-source chain (bundle → user-picker bookmark → HF cache prefetch) returning a resolved URL with active scope handle.
   - `GraniteSpeechRuntime.swift` — actor wrapping `MLXAudioSTT.GraniteSpeechModel.fromPretrained`. Holds security scope for the lifetime of the loaded weights. `prime() / transcribeStream(audio:) / unload()`. Whatever shape `fromPretrained` actually wants (HF model ID with cache redirect, or local URL) gets bound here once the agent reads `Sources/MLXAudioSTT/Models/GraniteSpeech/GraniteSpeech.swift`.
   - Tests: bookmark round-trip, resolver fallthrough, mock-URL scope dance.

2. **App target patches** (UI + plumbing, allowed in app target per AGENTS.md):
   - `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` — replace the 36-line placeholder body. Mic capture reuses the gainProvider + AudioLevels pattern from `SpeechRecognizer.swift`; the audio buffer feeds `GraniteSpeechRuntime.transcribeStream(audio:)` via `mlx-audio-swift`'s streaming API.
   - Settings overlay (find current location) — add **"Select Granite Speech Model Folder"** row that fires `UIDocumentPickerViewController` in `.open` mode for `.folder`. Selection writes to `GraniteSpeechBookmarkStore`. Status text shows "Not selected" / "Selected: <folder name>" / "Stale — re-select".
   - `TCCC_IOS/DevTools/` — new `GraniteLiveView.swift` (DevTools-style isolated demo screen). Live transcript pane, RAM gauge, peak-memory readout, latency-per-chunk readout. **Does not** wire into the main 5-screen pager; lives behind the existing DevTools card on the splash.
   - `project.yml` — add `mlx-audio-swift` package, add `TCCCAudio` local package, add product links on the app target.
   - **No DevTools entry collisions** — `DevToolsLandingView.swift` already exists; new "Granite Live" tile gets added there.

3. **Out of scope for Sprint 1** (deferred to Sprint 2/3):
   - Wiring Granite Speech transcripts into `LiveCaptureScreen` for the main pager.
   - Wiring Granite Speech transcripts into `HotSeatPacketBuilder` → text-LLM patch generation. (Possible to demo in Sprint 1's DevTools view, but not required.)
   - 8-bit / mxfp4 / 4.1-2b model variants.
   - Cutover from Apple Speech as the runtime default.

## Architectural placement: TCCCKit vs new package

**Decision: new `Packages/TCCCAudio` package.**

Rationale:
- `mlx-audio-swift` is a heavy SDK dep (depends on mlx-swift, MLXNN, etc.) — same character as AnyLanguageModel which is already isolated in `Packages/TCCCLLM`.
- TCCCKit's existing modules (`TCCCDomain`, `TCCCExtractor`, `TCCCReports`, `TCCCDesign`) are pure-logic with no external SDK deps. Adding mlx-audio-swift to TCCCKit would change its character and slow its tests.
- The TCCCLLM shim package is the established precedent for "heavy MLX dep wrapped in a thin local Swift package" — `TCCCAudio` mirrors that exactly.
- TCCCAudio depends on TCCCKit for any shared types it needs (none required at the moment — the resolver/bookmark/runtime trio is self-contained, and `RecognitionUpdate` / `TranscriptStream` already live in the app target).

**Existing-file placement caveat:** `TranscriptStream` protocol, `RecognitionUpdate`, `TranscriptSegmentLedger`, and the existing `SpeechRecognizer` / `ParakeetTranscriptStream` actors all live in the **app target** (`TCCC_IOS/Audio/`). That's a pre-existing AGENTS.md violation, not introduced by this sprint. Sprint 1 does **not** touch their placement; relocating them is out of scope and would balloon the sprint. The new package's `GraniteSpeechRuntime` is callable from the app target's `GraniteSpeechTranscriptStream` placeholder — that's the thin app-target → package boundary.

## Open questions remaining (to confirm before final design doc)

1. **Settings overlay location.** Where does the new "Select Granite Speech Model Folder" button live in the existing Settings UI? Need a `find` for the Settings overlay file before writing the patch.
2. **Bookmark stale-recovery UX.** On stale resolution, does the runtime automatically re-fire the picker, or does it fail with a banner that says "Re-select model folder"? Spec defaults to the latter (no surprise UI) unless directed otherwise.
3. **DevTools view scope.** Does the Sprint 1 demo view show only the live transcript, or does it also pipe transcripts into `HotSeatPacketBuilder` to demonstrate patch generation end-to-end? The latter is more impressive but may overrun Sprint 1.
4. **Mlx-audio-swift pin.** README says `branch: "main"` but production should pin a tag/commit. Need to fetch the latest release tag before writing project.yml patch.

After these are answered, the design doc goes to `docs/superpowers/specs/2026-05-10-granite-speech-foundation-design.md`.
