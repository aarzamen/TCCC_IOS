# Granite Hot Seat Sprint 2 Plan

## Goal

Continue after Sprint 1 by putting Granite behind the hot-seat boundary
without weakening the app's existing safety posture:

- Apple Foundation Models remains the default text backend.
- Apple Speech and Parakeet remain the operational ASR defaults.
- Granite can only produce candidate patches or critiques.
- Validators and operator review decide what is usable.
- No Generate, Record, Clean, Review, or Transmit path can start a model
  download.

## Task 1: Granite Text Backend And Structured Patch Facade

Status: implemented.

Files:

- `TCCC_IOS/Intelligence/GraniteTextLLMBackend.swift`
- `TCCC_IOS/Intelligence/GraniteGeneratedCandidatePatch.swift`
- `TCCC_IOS/Intelligence/GraniteHotSeatGenerator.swift`
- `TCCC_IOS/Intelligence/MLXBackend.swift`
- `TCCC_IOS/App/AppState.swift`
- `TCCC_IOS/Components/SettingsOverlay.swift`
- `TCCC_IOS/Components/FMStatusBadge.swift`
- `TCCC_IOSTests/LLMBackendPolicyTests.swift`
- `TCCC_IOSTests/GraniteHotSeatGeneratorTests.swift`

Acceptance:

- Granite is an explicit alternate backend using
  `mlx-community/granite-4.0-h-1b-base-4bit`.
- Missing MLX weights throw `modelNotProvided` before any model loader can
  download.
- Structured patch output uses AnyLanguageModel `@Generable` DTOs.
- Malformed fallback text output is rejected.
- Validation errors stop the candidate patch before review.

## Task 2: Review Action Wiring

Status: implemented.

Added an explicit hot-seat review action that builds a `HotSeatPacket`
from the transcript ledger, calls `GraniteHotSeatGenerator.candidatePatch`,
and appends the result to the existing review queue after validation. This
does not mutate `PatientState`; invalid candidate patches become held
review items.

Tests first:

- unavailable Granite backend appends a system status, not a crash.
- accepted patch enters `graniteReviewQueue`.
- rejected patch is held with validation errors.
- primary patient snapshot is unchanged before and after.

## Task 3: Granite Speech TranscriptStream Scaffold

Status: implemented as unavailable scaffold.

Add a `GraniteSpeechTranscriptStream` type that conforms to
`TranscriptStream` but reports unavailable until a Swift runtime exists.
Do not add weights, MLX audio code, or a Record-button download path in
this task.

Acceptance:

- The app can represent Granite Speech in backend selection state.
- Selecting it cannot silently network.
- Attempting to start while unavailable returns a controlled error.

## Task 4: WhisperKit Bake-Off Harness

Status: specified in `docs/granite/specs/asr_bakeoff_protocol.yaml`.

Create a local-only ASR comparison harness with shared audio clips and a
TCCC keyword list. It should compare available ASR backends by transcript
quality, keyword misses, and latency. WhisperKit integration itself should
stay behind explicit operator/model setup until benchmarked.

Acceptance:

- Same audio segments feed each backend.
- Outputs include WER-ish distance, TCCC keyword misses, and timing.
- No cloud dependency.

## Task 5: Device Memory And Thermal Profiling

Status: specified in `docs/granite/specs/device_profile_protocol.yaml`.

Measure Granite text model load and constrained generation on the iPhone
17 Pro before any operational UI depends on it.

Acceptance:

- cold load time recorded.
- first token / patch completion time recorded.
- peak resident memory recorded.
- thermal state and memory headroom logged.
- fallback thresholds documented.

## Task 6: Report-Level Granite Critique

Status: implemented as schema and validator.

Granite may critique deterministic 9-Line, ZMIST, and DD-1380 output, but
it must not rewrite those reports directly. The critique output is a
schema with evidence IDs, suspected omissions, conflicts, and suggested
review prompts.

Acceptance:

- deterministic report remains display/export ground truth.
- critique is schema-bound.
- unknown or unsupported claims are held for review.
- validators decide whether the critique is actionable.

## Verification

Run before claiming Sprint 2 work is ready:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS
xcodegen generate
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation
```

For package-only changes:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS/Packages/TCCCKit
swift test
```
