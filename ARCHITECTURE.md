DRAFT

# TCCC.ai iOS: a walkthrough map

This is the map for a code walkthrough, written for a self-taught builder. Eight
stops follow the data: what the app may be, how the record is kept, how a spoken
sentence becomes a finding, how findings become DD Form 1380 fields, how the
official form is filled, how everything is saved, where speech comes in, and
where the pulse oximeter comes in. Each stop says what the code does, why it
exists, and what breaks if it is changed carelessly.

Safe to ignore on a first pass: generated code and boilerplate
(`TCCC_IOS.xcodeproj`, written by xcodegen from `project.yml`, never hand-edited;
`TCCC_IOS/Generated/Info.plist`; `.build/`; the SwiftUI visual pieces in
`TCCC_IOS/Chrome/`, `Components/` and `Design/`), and vendored or wrapped
libraries (`Packages/TCCCLLM` and `Packages/TCCCAudio` are thin shims around
MLX, AnyLanguageModel and mlx-audio-swift). `TCCC_IOS/DevTools/`,
`TCCC_IOS/TranscriptionLab/` (Yap Lab) and the alternative backends
(`Audio/Parakeet*`, `Audio/Granite*`, `Intelligence/Granite*`,
`LFM2LLMBackend.swift`, `QwenLLMBackend.swift`) are leaving in v1.0.

## 1. What v1.0 is, and the rules everything obeys

`docs/SCOPE.md`, then the "Hard product constraints" and "Core invariants"
sections of `CLAUDE.md`. SCOPE declares v1.0 a stopping point: five screens,
Apple Speech (Qwen3-ASR planned), the S5W pulse oximeter, encrypted persistence,
and one deliverable, a filled-in official DD Form 1380 at the end of care. The
9-line and ZMIST may stay approximate. The constraints are the rules the code
obeys: offline (no network with casualty data; speech and language models run on
the device), landscape-only iPhone, gloved-hand targets, encrypted files, and one
writer of clinical state, the engine. A change that needs a network client, a
portrait layout, or a view that edits patient state directly is refused here,
before any code is read.

## 2. The record is a replayable list of events

`Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift`.
`processTranscript(_:timestamp:backend:)` takes one transcript chunk, normalizes
spoken numbers, splits sentences, runs the extractors in the fixed order of
`PatientStateEngine+Standard.swift`, then `emitEvents` records what changed: an
`asrSegment` event with the words and one `deterministicFact` per changed field,
found by `diff` in `PatientStateProjection.swift`. The record is that log, not
the state. `project(_:)` folds the log back into state by replaying the recorded
deltas and never re-runs an extractor; `restore(_:)` uses it after a crash. The
binding invariant, checked by `LogEquivalenceTests` and `EngineInvariantTests`:

```
patients == PatientStateEngine.project(log)
```

This buys exact recovery after a crash, and history that does not change when a
regex changes. It breaks if a field is written outside `diff` (never saved, lost
on restore) or if `project` is made to re-run extractors.

## 3. One sentence becomes a MARCH finding

`Packages/TCCCKit/Sources/TCCCExtractor/HemorrhageExtractor.swift`, the M of
MARCH and typical of all eleven extractors. `apply(_:context:)` takes one
sentence and returns new state: a negative pass first ("no bleeding" marks
hemorrhage assessed, not identified), then the positive pass, location patterns
from specific to general, then tourniquet, pressure dressing and "controlled".
It ports `_extract_hemorrhage` from the TCCC_FEB_2026 Python prototype,
`src/state.py`; its test, `Tests/TCCCExtractorTests/HemorrhageExtractorTests.swift`,
copies the Python assertions verbatim. Those tests are the contract because
they were proven on real scenario text first; Swift-only tests are added on top,
never instead. It breaks if the passes are reordered or a pattern is "improved"
without rerunning the fixtures in `Tests/TCCCExtractorTests/Resources/scenarios/`.

## 4. Engine state becomes DD 1380 fields

`Packages/TCCCKit/Sources/TCCCReports/DD1380Mapper.swift` and
`DD1380CardData.swift`, read against
`reference/rubric/extracted/dd1380_field_inventory.json`, the verbatim list of
the fifty official fields. `DD1380CardData` is the field model, sections A to H.
`DD1380Mapper.map(_:)` fills it through small helpers: `mechanism(from:)`,
`tourniquets(from:)`, `treatments(from:)`, `medications(from:)`,
`otherTreatments(from:)`, `notes(from:mechanism:)`. `DD1380Readiness.evaluate`
only reports what is missing; a partial card beats none. Check this stop line by
line, because it feeds the deliverable. The rule is blank, never invented: no
NKDA unless entered, no tourniquet type unless the medic named the device, no
body-diagram coordinates. It breaks the moment an inference is added.

## 5. The official form is repaired, renamed and filled

`tools/repair_dd1380_jul2025.py` fixes the owner's JUL 2025 copy, whose
encryption is damaged, by finding each object's original number and decrypting
it with the right key. `tools/prepare_dd1380_template.py` keeps the official
drawing and fonts, renames all 305 fields to flat names (`FIELD_MAP`), and writes
`TCCC_IOS/Resources/DD1380/DD1380_JUL2025_template.pdf` plus a JSON manifest.
`Packages/TCCCKit/Sources/TCCCReports/DD1380OfficialForm.swift` maps card data to
those names: `values(for:cardNumber:)` fills rows and sends the rest to Notes,
`splitNotes` cuts what does not fit, and `cardSet(for:)` adds a card labelled
"#2" so nothing is dropped. `TCCC_IOS/App/DD1380OfficialFormFiller.swift` is the
only PDFKit code: `render(_:bundle:)` fills the widgets, `shrinkToFit` keeps
values inside narrow boxes, and the result is flattened. It breaks if a field is
renamed without regenerating the manifest, if row counts change without checking
overflow, or if anything maps by the form's original names, which are wrong in
places.

## 6. The app feeds the engine and writes protected files

`TCCC_IOS/App/AppState.swift`: a committed line goes through
`processWithEngine(_:timestamp:)`, `refreshPatientSnapshot` copies state for the
views, `persistNewEvents` appends only new, settled events, and
`makeDD1380Card()` is the export seam. `TCCC_IOS/App/EncounterStore.swift` is an
actor owning all encounter I/O: `appendToActive` writes one JSON line per event
to `Documents/encounters/<id>/events.jsonl` through `ProtectedWrite`, which sets
`NSFileProtectionComplete` on every write; `loadActiveEncounter` is the replay
path for `AppState.load()`. `newPatient()` and `endCurrentCare()` call
`archiveActive` (archive, never delete); `wipeSession()` calls `purgeAll` after a
three-second hold. It breaks if a casualty file is written without
`ProtectedWrite`, if a provisional chunk is persisted before it settles, or if an
archive becomes a delete.

## 7. Apple Speech capture, and where speech errors enter

`TCCC_IOS/Audio/SpeechRecognizer.swift`, an actor around `SFSpeechRecognizer`.
`prime()` starts the microphone and a 30-second ring buffer so the medic can
talk before tapping record; `start(audioURL:)` drains that pre-roll into the
recognizer; `stop()` keeps a 30-second tail so the last sentence survives.
`SpeechRequestFactory.configure` sets `requiresOnDeviceRecognition = true`, the
offline rule in code. `TCCC_IOS/Audio/SpeechUtteranceAssembler.swift` stitches
callbacks into one transcript; its timing rules exist because long requests
reset the hypothesis at utterance boundaries and a naive replace lost earlier
speech. Errors enter in `handleResult`, which hands text to
`AppState.receiveAppleCapture`; from there the words are evidence in the log.
Medical words (tourniquet, tranexamic acid, drug names) are the known weak spot,
and corrections live only in the engine's deterministic normalizers, never in a
language model. It breaks if the on-device flag is loosened or the assembler's
rules change without the device traces behind them.

## 8. The S5W pulse oximeter: decode, associate, record as unvalidated

`Packages/TCCCKit/Sources/TCCCDomain/PulseOximeter.swift`:
`LepuPulseOximeterDecoder` turns notification bytes into `PulseOximeterPacket`
values (reading, waveform, unknown), checks each frame with `crc8Maxim`, and
keeps every raw frame and receipt time. `TCCC_IOS/Sensors/PulseOximeterBluetooth.swift`
is the Core Bluetooth transport (`start()`, `setEnabled(_:)`, `selectDevice(_:)`,
`Status`); it never decodes or stores, and only `markValidReadingReceived`
can show "receiving". Nothing enters the record without explicit association:
`PatientStateEngine.associateSensor` binds one device to one casualty, and
`recordSensorObservation` accepts readings only for that binding, logging a
`sensorObservation` event with the exact deltas applied. Auto-connect off, a new
casualty, End Care or a restart clears the authority; a replayed log never grants
it. "Unvalidated" means a consumer sensor of unknown signal quality, times are
receipt times, and a connection is not proof of a valid reading. It breaks if
anything ingests before association, decodes inside the transport, or drops the
unvalidated label from a display or export.
