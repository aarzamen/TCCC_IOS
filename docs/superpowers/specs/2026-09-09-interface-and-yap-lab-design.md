# Field interface, offline assets and Yap Lab

User-authorized scope: repair the reviewed interface; provide an interactive system explorer; implement a splash-accessible local transcription sidecar with independent ASR/LLM choices and editable prompt presets; prepare assets for offline installs. Retain the splash with three choices because the latest request explicitly requires it.

## Boundaries

Clinical state remains event-sourced and written only by the engine. Lab transcripts and model output never enter an active casualty. Raw recognition remains visible beside optional transformation. No inference action may initiate a network download. Downloads and offline package preparation are explicit installation work. Apple-owned Speech/Foundation assets cannot be redistributed as app weights: readiness must describe their actual availability.

Use the existing Swift 6 / SwiftUI, iOS 26 landscape app, pinned dependencies and protected file writing. Reuse model files and backend implementations across clinical and lab flows. Tests use synthetic material; private recordings and downloaded weights stay out of Git.

## Deliverables

1. Repair clinical UI: honest manual review and operational 9-line fields, no invented completion, useful durable clinical entry actions, no fake camera/wired-export controls, truthful QR/share labels, scoped MEDEVAC draft validity, visible export errors, functional haptic preference. Preserve incomplete-document export.
2. Yap Lab: `YapLabView(state:onBack:)`, independent session manager; live capture plus local audio import; raw transcript; editable system and task prompts with presets; independent ASR and LLM choices; visible availability/busy/error states; cancellation, save/reopen and share local sessions; no hidden clinical extraction. Provide repeatable pairing comparisons without fabricated performance claims.
3. Offline model preparation: one consistent local resolver across assets, inspectable install readiness, operator-controlled preparation, durable storage/bundled asset support and reproducible field-install packaging. Verify actual files before claiming installed. Document Apple system-asset constraints and model distribution provenance.
4. Interactive system explorer: playable, synthetic flow from sound to report, model selectors, click-to-inspect subsystem boundaries and failure controls. Explain evidence versus model suggestions; demonstrate that a language model does not repair missing source evidence by magic. Clearly label simulated behavior and measured versus unmeasured performance.

## Verification

Focused regressions for correction persistence, unknown 9-line fields, stale drafts, backend readiness, lab raw-text preservation and cancellation. One package suite and simulator integration suite after integration; signed device build and in-place update if connected and idle. Inspect the new UI and explorer. Report which physical inference paths were exercised. Source-only green checks never imply model quality or offline readiness.
