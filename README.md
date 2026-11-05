# TCCC.ai iOS

Combat-medic documentation app for iPhone (bundle name "Swift TCCC"). Voice
intake → on-device speech recognition → deterministic state extraction
(MARCH/PAWS, vitals, mechanism of injury) → a filled-in, official **DD Form
1380** produced at the end of care, plus an approximate 9-line MEDEVAC and
ZMIST handoff. Landscape, chest-mounted, and offline for everything that
touches casualty data.

**v1.0 is a declared stopping point**, decided 2026-10-27 in
[docs/SCOPE.md](docs/SCOPE.md): what exists today minus anything broken or
half-built, plus the one deliverable this app was always for, the DD 1380. The
9-line and ZMIST are happy accidents along the way and may stay approximate.
The DD 1380 cannot.

> **Status: working prototype, not a cleared medical device.** It runs
> end-to-end on an iPhone 17 Pro and has captured real dictation, but it has not
> been clinically validated, security-audited or certified for operational use.

## What v1.0 is

- **Five screens:** Live Capture, Vital Signs Log (DD 1380 §C), TCCC Card,
  MEDEVAC (GPS Line 1) and Handoff.
- **Speech recognition:** Apple Speech, on-device only
  (`requiresOnDeviceRecognition = true`), with a 30-second pre-roll and a
  30-second tail. **Qwen3-ASR 0.6B** (on-device, optional) is the planned
  second option; it is not in this build yet.
- **Language model:** Apple Foundation Models, on-device, for optional drafts
  only (narrative, ZMIST wording, radio script). No language model writes the
  DD 1380 or any clinical state.
- **Vibeat S5W pulse oximeter** over local Bluetooth, labelled as an
  unvalidated consumer sensor. Readings enter the record only after the
  operator associates the sensor with the current casualty.
- **Continuous encrypted persistence:** crash recovery, New / End archive, Wipe.
- **Exports:** DD 1380 PDF (the official JUL 2025 form), JSON, audio +
  transcript, vitals CSV, offline QR.
- **Build stamp** in Settings → System: version, build number, git SHA, branch,
  build date.

## What this build still carries

SCOPE removes these before the v1.0 tag. They are present in the tree today and
are not part of the supported configuration:

- **Yap Lab** (`TCCC_IOS/TranscriptionLab/`), an audio-and-transcription
  experiment workspace, and **DevTools** (scenario playback, Granite
  diagnostics), both still reachable from the launcher.
- **Alternative backends** still listed in Settings: Parakeet and Granite
  Speech for speech; LFM2.5, Qwen 3 1.7B and Granite text for the language
  model. Their weights leave the offline model pack with them.
- Dead scaffolding: the NFC handoff destination (disabled), the DevTools
  "Receiver mode" placeholder, an unused placeholder view.
- No blood-pressure monitor or any sensor family other than the S5W. There is
  no generic `VitalsSensor` protocol; `PulseOximeter.swift` decodes the one
  observed stream.

## The five screens

| Screen | What it does today | Caveats |
|---|---|---|
| 01 Live Capture | On-device transcript with live partial previews; the engine extracts facts from finalized speech; two "Load demo" buttons seed the engine without speaking | Extraction runs on finalized segments, not partials. Medical words are the known weak spot (below) |
| 02 Vital Signs Log | DD 1380 Section C grid: the four most recent timestamped readings from speech, the pulse oximeter or **Add / correct reading** (manual entry through the engine) | Four readings on screen; the encounter log keeps the full stream |
| 03 TCCC Card | Front and back of the card: body diagram shading from recorded hemorrhage regions, MARCH (with hypothermia §7 and TBI §8 rows), PAWS, medications, §D–H fields; **Casualty details** and **Assessment** editors for identity, mechanism, injuries and precedence | Identity fields stay blank unless entered; unknown allergies never become NKDA |
| 04 MEDEVAC | 9-line with GPS Line 1 (WGS-84 → MGRS in-house), editable operational fields with explicit unknowns, radio worksheet | Approximate by design; "Call made" records an operator confirmation, nothing is transmitted |
| 05 Handoff | Structured ZMIST; optional Apple Foundation Models drafts; **DD-1380 PDF** export; JSON, audio + transcript, CSV; offline QR | Drafts need review; the QR confirms nothing about receipt |

## How the record is kept

`PatientState` is a projection of an append-only event log. The engine
(`PatientStateEngine`, in `Packages/TCCCKit`) is its sole writer; views, the
language model and the sensor path can only hand it evidence. Every event is
written continuously to `Documents/encounters/<id>/events.jsonl` with
`NSFileProtectionComplete`, so a mid-care crash replays on relaunch. **New
Casualty** and **End Care** archive the record (never delete); **WIPE** (hold
3 s) purges the archive. Encryption is set on every write; the
locked-device-unreadability property has not been independently audited.

## The DD 1380 export

Handoff fills the official **DD Form 1380, JUL 2025** from structured state
only: the same deterministic `DD1380Mapper` the card uses, no language model.
Fields that were never captured stay blank. A tourniquet device the medic names
("CAT") fills the limb box and the TQ type line; medication rows carry the drug
the medic named; notes that do not fit continue on a second official card
labelled "#2". The injury-diagram boxes are not marked yet (injury locations go
to Notes); there is no roster integration. The template in
`TCCC_IOS/Resources/DD1380/` is produced by `tools/prepare_dd1380_template.py`
from a repaired copy of the official PDF (`tools/repair_dd1380_jul2025.py`).

**Review every extracted intervention before export.** Speech recognition still
misses medical words; the 2026-09-08 benchmark failed 2 of 8 fields on
tourniquet / tranexamic-acid recognition. Errors seen on device are repaired
deterministically where they recur (`MedicalTermNormalizer`), never guessed.

## Pulse oximeter

Auto-connect to a supported S5W is on by default, with a persistent toggle and
connection status in Settings. The transport only discovers, connects and
subscribes; decoding is pure code in `PulseOximeter.swift`; nothing enters the
record until the operator associates the sensor with the casualty, and that
authority ends with Stop/Off, a new casualty, End Care or an app restart.
Values are recorded as unvalidated consumer-sensor measurements with receipt
times and raw frames kept as evidence. Open physical checks are listed in
[the validation record](docs/testing/2026-09-18-wireless-vitals-validation.md).

## Accepted limits in v1.0

- Not a cleared medical device; not clinically validated or security-audited.
- The 9-line and ZMIST are approximations for the operator to check.
- Pulse-oximeter values are unvalidated.
- Medical-word speech errors (tourniquet, tranexamic acid) still occur; review
  every extracted intervention before handoff.
- Identity fields are blank unless entered on the TCCC Card.

## Build and test

`project.yml` is the source of truth; the `.xcodeproj` is generated. The
signing team ID is not in git: copy `Config/Signing.xcconfig.example` to
`Config/Signing.xcconfig` for device builds (see `APPLE_DEVELOPER_WARNING.md`).

```bash
xcodegen generate
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

`-skipMacroValidation` is required for CLI builds (`AnyLanguageModel` ships
Swift macros). The Metal toolchain may be needed once on a fresh Mac
(`xcodebuild -downloadComponent MetalToolchain`).

```bash
# all clinical logic, no simulator needed; also runs on Linux with Swift 6.2
cd Packages/TCCCKit && swift test
```

```bash
# app-target tests need a booted simulator
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

Device install: `xcodebuild … -destination 'generic/platform=iOS' build`, then
`xcrun devicectl device install app --device <id> <path>.app` and
`xcrun devicectl device process launch --device <id> com.aarzamen.TCCCai`.
`scripts/archive_and_export.sh` produces a signed `TCCC-<version>-<sha>.ipa`.

Dated test evidence: TCCCKit 992 tests, 0 failures (2026-11-05, Linux); app
target 242 tests, 3 expected skips, 0 failures (2026-09-09, simulator). CI
(`.github/workflows/ci.yml`) runs the package tests and a simulator build.

## Repository layout

```
project.yml                  # xcodegen spec, source of truth
TCCC_IOS/                    # SwiftUI app target (thin shell)
  App/                       # AppState, EncounterStore (persistence), exports, DD 1380 filler
  Audio/                     # SpeechRecognizer, utterance assembler, alt-backend streams (leaving)
  Sensors/                   # Core Bluetooth S5W transport
  Screens/ Pager/ Chrome/ Components/ Design/
  Intelligence/              # Apple FM backend; alt LLM backends (leaving)
  DevTools/ TranscriptionLab/  # leaving in v1.0
  Resources/DD1380/          # official form template + field manifest
Packages/TCCCKit/            # all clinical logic, testable without a simulator
  Sources/TCCCDomain/        # PatientState, MARCH/PAWS, Vitals, MGRS, PulseOximeter decoder
  Sources/TCCCExtractor/     # engine, event log, projection, extractors, normalizers
  Sources/TCCCReports/       # DD 1380 mapper + official-form values, 9-line, ZMIST, validators
Packages/TCCCLLM, TCCCAudio  # thin shims around MLX / AnyLanguageModel / mlx-audio-swift
reference/rubric/extracted/  # DD 1380 field inventory + 2026 TCCC vocabulary (JSON)
tools/ scripts/              # DD 1380 template tooling, model staging, archive/export
docs/                        # SCOPE.md, specs, plans, testing records, history/
```

Where to read next: [ARCHITECTURE.md](ARCHITECTURE.md) (walkthrough map,
draft), [docs/SCOPE.md](docs/SCOPE.md), [CLAUDE.md](CLAUDE.md) (constraints
and invariants), [THIRD_PARTY.md](THIRD_PARTY.md).

## Clinical alignment

Extraction is aligned to the 01 May 2026 TCCC Guidelines and the DD Form
1380. The field inventory and MARCH/PAWS vocabulary live in
`reference/rubric/extracted/` as JSON, extracted verbatim from JTS/CoTCCC
sources. A clinical display element must trace to a DD 1380 field or a
MARCH/PAWS phase-status change.

## Origin

Port of the TCCC_FEB_2026 Python prototype (a private repository). The Python
prototype's tests are the correctness contract; the Swift port mirrors the
assertions verbatim and builds the event-sourcing and UI layers on top.

## Licence

MIT; see [LICENSE](LICENSE). Third-party terms are listed in
[THIRD_PARTY.md](THIRD_PARTY.md): the SwiftPM dependencies are MIT or
Apache-2.0, DD Form 1380 is a United States government form, the rubric
extracts are US government works, and model weights are not in this repository
(the planned Qwen3-ASR weights are Apache-2.0).
