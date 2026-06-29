# Swift TCCC

iOS app for documenting Tactical Combat Casualty Care (TCCC)
encounters. Voice intake → on-device speech recognition →
deterministic state extraction (MARCH/PAWS, vitals, MOI) → DD Form
1380 sections + 9-line MEDEVAC + ZMIST handoff.

The app runs entirely on-device. It does not send casualty data over
the network — there is no client for ATAK, MEDHUB, or any other
external system, and no telemetry, analytics, or cloud-based
transcription. Outputs are files (JSON, audio, transcript, CSV) the
user shares manually via the iOS share sheet, plus an offline QR code
generated locally for scanning by another device. The only network
activity in the entire app is the optional, operator-gated one-time
model download for the alternate ASR/LLM backends (see below); the
default backends download nothing.

> **Status: working prototype, not a cleared medical device.** It runs
> end-to-end on an iPhone 17 Pro and has been used to capture real
> dictation, but it has not been clinically validated, security-audited,
> or certified for operational use. Treat it as an engineering prototype.

## What actually works today

Verified on an iPhone 17 Pro (iOS 26.x) and in the iOS Simulator.

| Screen | Works | Not yet / caveats |
|---|---|---|
| 01 Live Capture | On-device ASR with live transcript; engine-extracted facts panel; 30 s pre-roll + 30 s tail; two "Load demo" buttons to seed the engine without speaking | Engine runs on committed lines, not partials |
| 02 Vital Signs Log | DD 1380 Section C grid (4 timestamped columns × 7 rows) populated from engine snapshots; interventions panel | **Cells are read-only** — tap-to-edit is not built |
| 03 TCCC Card | Anterior + posterior body diagram, MARCH (incl. Hypothermia §7 + TBI §8 sub-rows), PAWS, meds log, front/back card with §D–H scaffold | §D–H fields are best-effort from extracted state; not all are populated |
| 04 MEDEVAC | Auto-populated 9-line (incl. in-house WGS-84→MGRS for Line 1), voice-readable transmit script | **"Transmit" produces a script and logs an event — there is no over-the-air transmission of any kind** |
| 05 Handoff | Encounter summary, timeline, on-device LLM narrative + ZMIST, JSON / audio+transcript / CSV exports, offline QR | **DD-1380 PDF export is not implemented** (card shows "Pending PDFKit") |

**Lifecycle & persistence (shipped, device-validated):** each casualty's
encounter is an append-only event log written continuously to disk
(`Documents/encounters/<id>/events.jsonl` + a manifest), so a mid-care
crash recovers the in-progress encounter on relaunch. New Casualty / End
Care **archive** the record (never delete); WIPE (hold 3 s) purges the
whole archive and re-arms a fresh casualty. Every write is made with
`NSFileProtectionComplete`. (Encryption is code-set on every write; the
locked-device-unreadability property has not been independently audited.)

## Transcript pipeline

The streaming-ASR commit path is **loss-safe and identity-scoped**:

- Speech is committed to the on-screen transcript as soon as a short
  silence settles (a "provisional" line), so nothing is lost to a
  missing or late recognizer finalization.
- When the recognizer revises its words (e.g. "high-end" → "high and
  tight"), the **refined text replaces the provisional line in place**
  and the extraction engine supersedes that chunk's derived facts —
  refined words win in both the transcript and the structured record,
  with the originally-heard text retained in the audit log.
- There is no lexical de-duplication heuristic; replacement is scoped by
  chunk identity, which eliminates the duplicate/fragment artifacts the
  earlier approach produced.

This is implemented as an event-sourced projection: `PatientState` is a
deterministic fold over the event log, the engine is the sole writer of
state, and the LLM never mutates state. The design and implementation
notes live in `docs/superpowers/specs/` and `docs/superpowers/plans/`
(`2026-06-28-asr-provisional-replace*`).

## Clinical alignment

The extraction layer is aligned to the 01 May 2026 TCCC Guidelines and
the DD Form 1380. The field inventory and MARCH/PAWS vocabulary live in
`reference/rubric/extracted/` as JSON, extracted verbatim from JTS/CoTCCC
sources; the extractor patterns and DD-1380-bound UI elements reference
them directly. New UI elements are intended to trace to a DD 1380 field
or a MARCH/PAWS phase-status change. See `CLAUDE.md` for the audit log.

## Tests

- **TCCCKit (pure logic): 768 unit tests, 0 failures** — run in isolation
  with `swift test`, no simulator needed. These mirror the Python
  prototype's assertions plus Swift-only coverage of the event-sourcing
  fold, projection equivalence, and the transcript pipeline.
- **App target: 92 tests, 0 failures** — AppState lifecycle, persistence,
  exports, and provisional-replace behavior.

There is no end-to-end UI-automation suite; on-device behavior is
validated manually.

## Architecture

```
TCCC_IOS/
├── TCCC_IOS.xcodeproj         # generated by xcodegen — never hand-edit
├── project.yml                 # source of truth for Xcode config
├── TCCC_IOS/                   # SwiftUI app target (thin shell)
│   ├── App/                    # AppState, lifecycle, EncounterStore (persistence), exports
│   ├── Audio/                  # SpeechRecognizer, Parakeet + Granite streams, TranscriptStream
│   ├── Chrome/ Components/      # StatusStrip, PageHeader, Panel, FooterHints, SettingsOverlay
│   ├── Design/                 # Theme tokens, typography, layout
│   ├── Intelligence/           # TCCCLLMBackend conformers (Apple FM / LFM2 / Qwen / Granite)
│   ├── DevTools/               # dev-only Granite audio benchmark (launch-arg gated), not in normal runtime
│   ├── Pager/ Screens/          # 5-screen swipe pager + screen views
├── Packages/TCCCKit/           # local SPM — pure logic, testable in isolation
│   └── Sources/
│       ├── TCCCDomain/         # PatientState, MARCHState, Vitals, MGRS, enums
│       ├── TCCCExtractor/      # PatientStateEngine, event log + projection, extractors, normalizer
│       ├── TCCCReports/        # 9-Line + ZMIST generators + validators
│       └── TCCCDesign/         # shared design tokens
└── reference/rubric/extracted/ # DD 1380 + 2026 TCCC Guidelines as JSON
```

All clinical logic, the event log, the projection, and the report
generators live in `TCCCKit` and are unit-testable without launching the
simulator. The app target is SwiftUI views, view models, audio, on-device
inference, and file I/O.

## Constraints

These shape the dependency choices in this repo:

1. **No networking with casualty data at runtime.** No Wi-Fi, Bluetooth,
   Cellular, UWB, or NFC clients are wired. No analytics, crash
   reporting, or telemetry. ASR uses `requiresOnDeviceRecognition = true`;
   the on-device LLM is on-device by design. The only network calls in
   the app are operator-gated one-time model downloads for the alternate
   backends (below), each a single HTTPS GET, cached locally thereafter.
2. Landscape-only, iPhone-only, locked in `project.yml`.
3. Data-at-rest protection via `NSFileProtectionComplete` on the data
   directory (not independently audited).
4. Minimum hit target 44 pt; long-press only for destructive actions,
   with a visual progress fill.
5. Default theme is Dark; Tactical (deep near-black + desaturated red) and
   Light are operator-selectable.

## ASR backends

Settings → Audio · ASR offers three backends. **Apple Speech is the
default and the only one validated for routine use; the other two are
experimental and require operator setup.**

- **Apple Speech** (default). `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition = true`. No download.
- **Parakeet (alt, experimental).** NVIDIA Parakeet TDT 0.6B v2 (English
  only) via FluidInference's
  [FluidAudio](https://github.com/FluidInference/FluidAudio). CoreML
  bundle downloads on first activation (~300 MB, one HTTPS GET, gated
  behind a Settings tap), cached thereafter.
- **Granite Speech (alt, experimental).** Requires the operator to point
  Settings → "Select Granite Speech Model Folder" at a local model bundle
  first; without it the backend refuses to start.

The 30 s pre-roll + 30 s tail and the Settings dynamic mic gain
(−20 to +20 dB) apply to all backends.

## On-device language model (narrative / ZMIST / radio script)

Settings exposes a three-way LLM backend picker. These power the optional
prose generation on Handoff/MEDEVAC; the structured DD-1380 record is
produced deterministically by the engine and does **not** depend on an LLM.

- **Apple Foundation Models** (default). On-device; on a fresh device the
  system model may still be downloading on first use, in which case
  generation reports "unavailable" until it finishes.
- **LFM2.5-1.2B-Instruct** and **Qwen 3 1.7B** (alt, experimental). MLX
  4-bit, via `huggingface/AnyLanguageModel`. Functional but require an
  explicit Settings-gated model download before first generation.
- A Granite text backend exists for an experimental "hot-seat" patch-review
  flow; it does not directly mutate clinical state.

Generated MEDEVAC/ZMIST text is cross-checked against engine state by
validators and falls back to the deterministic generators when the model
output disagrees.

## Build

```bash
# regenerate the .xcodeproj from project.yml
xcodegen generate

# build for simulator
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation
```

`-skipMacroValidation` is required for CLI builds because the
`AnyLanguageModel` dependency ships Swift macros that Xcode otherwise asks
you to trust interactively. On a fresh machine you may also need the Metal
toolchain once (`xcodebuild -downloadComponent MetalToolchain`) for
MLX-Swift's GPU kernels.

```bash
# run the kit unit tests in isolation (no simulator)
cd Packages/TCCCKit && swift test
```

Device install (free provisioning; substitute your team/device):

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS' -configuration Debug \
  -skipMacroValidation -allowProvisioningUpdates \
  -derivedDataPath /tmp/tccc-device-dd build

xcrun devicectl device install app --device <device-uuid> \
  /tmp/tccc-device-dd/Build/Products/Debug-iphoneos/TCCC_IOS.app
xcrun devicectl device process launch --device <device-uuid> com.aarzamen.TCCCai
```

`xcrun devicectl list devices` lists connected device UUIDs.

## Demo path

1. Live Capture is the default screen. Tap **Load demo · GSW thigh**
   (or **Load demo · Femur**) to seed the engine without speaking.
2. The EXTRACTED panel populates with engine-derived facts (MOI,
   hemorrhage location, vitals, classification, etc.).
3. Swipe through the five screens; each renders the same engine state.
4. On Handoff, **Narrative** and **ZMIST** invoke the selected on-device
   language model (if available) to produce prose summaries.
5. **JSON Encounter** and **Audio + Transcript** open the iOS share sheet
   with the corresponding files.
6. Hold **Transmit** for two seconds with **QR · OFFLINE** selected to
   render an offline QR code containing the patient JSON locally — nothing
   is sent.
7. Footer **NEW** / **END** / **WIPE** drive the casualty lifecycle, each
   with a confirmation step.

## Known gaps / not yet built

- DD-1380 PDF export (the rubric's primary deliverable) — stubbed.
- Section C grid tap-to-edit — read-only today.
- Over-the-air MEDEVAC transmission — intentionally absent (RF discipline);
  "Transmit" is script + logged event only.
- Sensor integration (ANT+ chest strap, Jetson companion) — no hardware
  exists; the `VitalsSensor` protocol is scaffolding.
- Alternate ASR/LLM backends — functional but experimental and gated
  behind operator downloads/setup.
- No formal security audit, no clinical validation, no CI-driven UI tests.

## Origin

Port of the Python prototype at `/Users/ama/TCCC_FEB_2026`. The Python
prototype's tests are the correctness contract; the Swift port mirrors the
assertions verbatim and builds the event-sourcing and UI layers on top.

## License

Personal project. Not currently licensed for distribution.
