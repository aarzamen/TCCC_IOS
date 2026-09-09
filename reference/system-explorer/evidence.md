# TCCC switchboard evidence

The adjacent HTML is an inline visualization fragment, not an app screen or an inference benchmark. It uses local synthetic state only and makes no network calls. The editable conversation copy is in the task's visualization directory. No medical recommendations are generated.

## Source boundaries inspected on 2026-09-09

| Map concept | Source |
| --- | --- |
| Audio, request/capture identity, finalization and errors | `TCCC_IOS/Audio/TranscriptStream.swift`; `TCCC_IOS/App/AppState.swift` |
| Finalized Apple/Parakeet extraction versus incomplete audit evidence; Granite compatibility path | `README.md`, Transcript pipeline; `AppState.swift`, capture evidence and commit handling |
| Spoken-number normalization and extractor passes | `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` |
| Engine-only clinical writes and event-sourced projection | `PatientStateEngine.swift`; `README.md`, Transcript pipeline |
| Structured report mapping; unknown identity/allergies remain blank | `Packages/TCCCKit/Sources/TCCCReports/DD1380Mapper.swift` |
| Apple Speech, Parakeet, Granite Speech; Apple FM, LFM2 and Qwen 3 choices | `README.md`, ASR backends and On-device language model |
| Optional MEDEVAC/ZMIST validation and deterministic fallback | `README.md`, On-device language model; `TCCCReports/MedevacValidator.swift` and `ZMISTValidator.swift` architecture references |
| Independent Yap Lab, shared adapters/assets, no clinical writes | `docs/superpowers/specs/2026-09-09-interface-and-yap-lab-design.md` |
| Bundled/installed model resolution and no inference-triggered download | Same sprint spec and implementation plan; labeled current sprint, not measured readiness |

The pulse example is a hand-authored teaching scenario. Its outputs are scripted, not an execution of the Swift extractor. All backend choices intentionally use the same simulation; selecting a model does not imply comparative accuracy, latency or memory measurements. The incomplete-segment demonstration models the committed-segment clinical path and labels Granite's compatibility difference in the selected raw-evidence detail. The blocked-ASR toggle represents unavailable system or local assets, not a live device probe. The lab shares the demonstration selectors but never runs the clinical extraction stages.

## Local browser verification

Verified using the visualize skill's standalone preview wrapper and headless installed Chrome through Playwright. No Simulator or device was used.

- Normal synthetic pulse reaches the mapped pulse field; unknown identity and allergies stay blank.
- Dropping the observation keyword leaves the pulse field blank.
- An incomplete segment does not enter clinical extraction in the modeled committed-segment path.
- Unavailable ASR stops new transcript/fact production and also blocks lab ASR.
- Draft disagreement invokes the demonstration fallback; disabling the LLM leaves deterministic reporting available.
- Automatic run traverses the observation and stops; selected subsystem details update independently.
- Viewports 736, 360 and 320 pixels fit without horizontal document overflow. Narrow and wide screenshots were inspected, including dark appearance. Labels were shortened after narrow inspection.
- No JavaScript page errors were observed. Runtime behavior is presentation-only; this does not validate app inference, clinical extraction or field audio quality.
