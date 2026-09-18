> Historical review of commit `2e1dec2` on 2026-09-09. Preserved below
> from the former orchestration workspace. Recheck each finding against
> current source before treating it as an open issue.

# TCCC interface review — 9 September 2026

Reviewed `/Users/ama/TCCC_IOS`, clean `main` at `2e1dec2`. Traced visible controls through their handlers, state, persistence and exports. Walked the existing iPhone 17 Pro / iOS 26.5 simulator build through the launch menu, Receiver, Sender, Bake-off and all five clinical pages. This review makes no source changes and does not operate on the physical iPhone.

The interface currently overstates several capabilities. The most consequential gaps concern correction, treatment logging, report readiness and the meaning of “transmit.” More visual polish should follow repair of these interactions.

## Prioritized findings

### 1. P1 — The 9-line can claim completion using invented defaults

An otherwise unassessed casualty displayed **9/9 COMPLETE** and enabled Transmit in the simulator. The form supplies `38.65 FM · MEDEVAC`, possible enemy, smoke/VS-17 marking, US military nationality and no CBRN contamination without operator entry. Unknown precedence becomes urgent; transport type is inferred. `isVerifiedForTransmit` only checks for a non-dash value and non-pending status. Setting a callsign in Settings does not change the form's default callsign because the screen does not pass that argument.

Evidence: [NineLineForm.swift:20](/Users/ama/TCCC_IOS/TCCC_IOS/App/NineLineForm.swift:20), [default values:45](/Users/ama/TCCC_IOS/TCCC_IOS/App/NineLineForm.swift:45), [operational fields:145](/Users/ama/TCCC_IOS/TCCC_IOS/App/NineLineForm.swift:145). Existing `NineLineFormTests` explicitly expect 9/9 after supplying only a patient and GPS; those assertions need to change with the behavior.

Repair: keep unentered facts unknown; make operational fields editable; distinguish entered, inferred and operator-confirmed values. Count actual confirmation rather than nonempty strings.

### 2. P1 — Treatment shortcuts do not record treatments

**TQ Apply / Log TQ**, **Med Given / Pick + dose**, **New Vital / Dictate** and **Photo / Wound** only append strings such as `MED GIVEN · pending dose`, then close the overlay. They open no editor, camera or recording flow. `appendSystem` only mutates the in-memory transcript; it does not enter the clinical event log. Mark uses the same temporary path. A user may export these messages in transcript text, but they do not become treatments or survive recovery through the clinical log.

Reproduced Med Given: the overlay closed, a system message appeared, and the card still showed **NO MEDICATIONS LOGGED**.

Evidence: [QuickActionsSheet.swift:87](/Users/ama/TCCC_IOS/TCCC_IOS/Components/QuickActionsSheet.swift:87), [appendSystem:786](/Users/ama/TCCC_IOS/TCCC_IOS/App/AppState.swift:786), [Live Capture duplicates:413](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/LiveCaptureScreen.swift:413).

Repair: make each supported shortcut open a small contextual entry sheet and save through the engine. Save Mark as a durable timestamped event. Remove Photo until capture and encounter attachment are implemented. Give success feedback only after a successful save.

### 3. P1 — Handoff misrepresents what Transmit does

The button says **Transmit / Hold 2s · AES-256**. The functional destination creates an ordinary JSON QR image; there is no payload encryption in `HandoffQR.payload`. Showing the QR immediately records a success message and sets `lastMedevacTransmitTime`, which causes the timeline to say **MEDEVAC requested**. Neither presentation nor successful rendering establishes that anyone received it. The separate MEDEVAC Transmit handler only appends a system message and has no sending or export path.

Evidence: [Handoff button:554](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/HandoffScreen.swift:554), [success bookkeeping:646](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/HandoffScreen.swift:646), [QR payload:348](/Users/ama/TCCC_IOS/TCCC_IOS/App/HandoffData.swift:348), [MEDEVAC handler:179](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/MedevacScreen.swift:179).

Repair: use **Show QR** and **Share documentation**. Treat **Radio call made** as a separate operator-recorded event. Remove the transport-encryption claim and selectable NFC placeholder. Describe QR presentation as presentation; do not assert receipt.

### 4. P1 — Generated MEDEVAC text can outlive its casualty or assessment

`generatedScript` belongs to the mounted MEDEVAC view. New casualty, End Care, changed observations and changed GPS do not invalidate it. An asynchronous generation can also complete after the casualty changes and publish its old result. The pager keeps the screen views mounted. This is a source-confirmed lifecycle gap; this review did not run model inference to reproduce it on device.

Evidence: [MedevacScreen.swift:8](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/MedevacScreen.swift:8), [generation publication:226](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/MedevacScreen.swift:226), [ScreenPager.swift:10](/Users/ama/TCCC_IOS/TCCC_IOS/Pager/ScreenPager.swift:10).

Repair: bind the draft and request to casualty identity and the report-input snapshot, using the same invalidation approach now used by Handoff drafts. Keep the deterministic current form available.

### 5. P1 — Entering Sender crashes during ambient metering

Reproduced twice in the simulator before entering a script. The crash is `EXC_BREAKPOINT / SIGTRAP`, with `_dispatch_assert_queue_fail` and `closure #1 in AmbientMeter.installTapAndStartEngine()` on `RealtimeMessenger.mServiceQueue`. The main-actor-isolated callback is being invoked on the audio callback queue. Its inner `Task { @MainActor ... }` does not prevent the entry assertion.

Evidence: [AmbientMeter.swift:82](/Users/ama/TCCC_IOS/TCCC_IOS/DevTools/Audio/AmbientMeter.swift:82). Local crash report: `/Users/ama/Library/Logs/DiagnosticReports/TCCC_IOS-2026-09-09-033704.ips`.

Repair: isolate audio-buffer handling from the UI executor, then publish only the sampled values to the main actor. Do not make scenario composition depend on ambient microphone sampling. Recheck on the physical iPhone after repair; this review establishes a simulator crash, not a fresh physical-device result.

### 6. P2 — Edit and Review do not provide a correction workflow

The pencil/**EDIT** badges on MEDEVAC rows are plain images and text. The **Review** button only appends `REVIEW · 9-LINE FIELDS`, invisible on that page. Both were reproduced. The vital grid and back-of-card are deliberately read-only; the casualty identity “fields” are also display-only `Text`, not input controls. A prompt to verify facts has limited value without a practical way to correct them.

Evidence: [NineLineRow.swift:69](/Users/ama/TCCC_IOS/TCCC_IOS/Components/NineLineRow.swift:69), [Review handler:175](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/MedevacScreen.swift:175), [VitalsScreen.swift:15](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/VitalsScreen.swift:15), [Field.swift:10](/Users/ama/TCCC_IOS/TCCC_IOS/Components/Field.swift:10).

Repair: one shared **Review & correct** workflow, opened at the relevant field from each deliverable. Save clinical corrections through the engine, retain provenance, and regenerate dependent outputs. Avoid separate conflicting copies of the same fact in PDF, card, ZMIST and MEDEVAC.

### 7. P2 — Three Settings switches have no advertised effect

Haptic Feedback, Lock Orientation and Auto-Export on Wired Handoff bind to booleans with no consumers elsewhere in the app. Haptics execute unconditionally. Orientation is fixed by the app configuration. There is no wired auto-export implementation. Voice Commands does have a consumer and should not be grouped with these inert switches.

Evidence: [SettingsOverlay.swift:535](/Users/ama/TCCC_IOS/TCCC_IOS/Components/SettingsOverlay.swift:535), [Haptics.swift:24](/Users/ama/TCCC_IOS/TCCC_IOS/Components/Haptics.swift:24), repository-wide reference search.

Repair: wire the haptic preference; present fixed orientation as information; remove unsupported wired auto-export. Audit persistence of operator preferences separately—several are plain in-memory properties.

### 8. P2 — Export labels hide important limitations

The narrow Handoff column truncates the DD-1380 title and its “9 blank” detail while preserving a bright **READY** pill. PDF availability is useful even for an incomplete card, but “can generate” and “clinically reviewed” must be distinct. Vitals CSV writes only the latest HR/BP/SpO2/RR snapshot with export-time timestamp, despite the app having a timestamped readings log. It omits the displayed AVPU/pain/history.

Evidence: simulator Handoff screen; [ExportCard.swift:34](/Users/ama/TCCC_IOS/TCCC_IOS/Components/ExportCard.swift:34), [CSV writer:399](/Users/ama/TCCC_IOS/TCCC_IOS/App/HandoffData.swift:399).

Repair: show a legible list of export names, with **Export draft · 9 missing** where appropriate. Export the readings log using observation times, or label the existing CSV explicitly as a current snapshot. Keep explanatory documentation outside the narrow action column.

### 9. P2 — Failures can look like ignored taps

PDF export catches errors and writes them only to the Capture transcript. JSON/CSV helpers return nil and their callers silently return. An operator on Handoff gets no local failure or retry explanation.

Evidence: [HandoffScreen.swift:428](/Users/ama/TCCC_IOS/TCCC_IOS/Screens/HandoffScreen.swift:428), [HandoffExports:378](/Users/ama/TCCC_IOS/TCCC_IOS/App/HandoffData.swift:378).

Repair: show progress and an inline error at the invoked action; retain the input and offer Retry.

## Export verification and remaining limits

Tapping DD-1380 generated a real 26,905-byte PDF in the simulator container (`Documents/DD1380_C-04_20260909-104034.pdf`, `%PDF-1.3` header). Both attempts initially showed a blank share panel. On the second attempt, a later observation confirmed the PDF thumbnail, filename, 27 KB size and normal Preview / Copy / Markup / Print / Save to Files choices. PDF generation and share-sheet presentation therefore work in this simulator; the cause and physical-device relevance of the initial loading delay are unestablished. No file was sent externally. Physical touch scrolling remains unverified; prior simulator gesture diagnostics were inconclusive.

## Which startup tools are worth keeping?

| Tool | Actual purpose and current limitation | Recommendation |
|---|---|---|
| Sender | Generates scenario speech using Kokoro, with Apple speech fallback, then offers playback. Useful for repeatable speaker-to-microphone ASR tests. Entry currently crashes in this simulator. | Keep; rename **Scenario playback**. Fix the crash and make ambient metering optional. |
| Receiver | Always opens “Receiver mode — coming soon.” No receiving implementation. | Remove from visible navigation. |
| Bake-off | Runs a bundled audio fixture through Granite Speech and records time, memory and keyword hits. It does not compare all ASR models. Requires a folder bookmark even though a cache resolver exists. The screen says READY while Run is disabled. | Keep under diagnostics; name the tested backend, show actual readiness, provide a model setup action in place. |
| Live | Records microphone input for Granite testing and processes it after Stop. Includes memory monitoring and a long-recording limitation notice. Also bookmark-gated. | Keep as an explicitly experimental Granite test. Do not present it as the ordinary live documentation path. |
| Transcription benchmark | Uses production Apple Speech configuration, reference scoring and saved result artifacts; launched with `--transcription-benchmark`. Not reachable from these menu cards. | This is the most useful existing harness for the present speech-coverage work. Expose it as **Run speech benchmark / View results**. |

Two further diagnostic defects: the voice picker offers non-American Kokoro voices that are silently mapped to `af_heart`, and the Kokoro path does not apply the visible pitch setting. Also, Bake-off displays a final `.result` when provided but computes its saved text/keyword scores from the token accumulator alone; a result-only stream could display text while saving an empty scored transcript. Sources: [voice mapping:341](/Users/ama/TCCC_IOS/TCCC_IOS/DevTools/TTS/KokoroEngine.swift:341), [synthesis parameters:318](/Users/ama/TCCC_IOS/TCCC_IOS/DevTools/TTS/KokoroEngine.swift:318), [Bake-off scoring:270](/Users/ama/TCCC_IOS/TCCC_IOS/DevTools/GraniteBakeoffView.swift:270).

## Recommended development order

1. **Make each action truthful.** Fix the Sender crash, remove unsupported actions/settings, replace fake Edit/Review affordances, repair MEDEVAC draft invalidation, and correct readiness/transmit claims. Add focused regressions for these actual failures.
2. **Close the documentation correction loop.** Provide one engine-backed editor for vitals, treatment details, identity and operational report fields. A correction must survive relaunch and agree across card, ZMIST and export. Start with the TQ/vital/medication actions the operator already sees.
3. **Make delivery straightforward.** A readable export list, visible progress/errors and a verified PDF/QR/share path. Check portrait-independent landscape layouts, gloved touch targets and physical scrolling on the phone. Move diagnostics into Settings and launch directly into casualty capture; retain active-encounter recovery.

Acceptance should exercise operator actions end to end: tap → entry → save → visible changed fact → restart → matching deliverable. Existing package/build checks remain valuable, but they do not establish that visible controls fulfill their promises. No full suite was rerun for this read-only source review.
