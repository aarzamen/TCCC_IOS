# Apple Speech Stack + Capture DSP + External Mics — Research (2026-07-02)

Compiled for the 2026-07-02 transcription sprint
(`docs/superpowers/specs/2026-07-02-transcription-and-fm-harness-sprint-design.md`).
Sources are Apple docs/WWDC unless marked **[community]**.

---

## 1. SpeechAnalyzer + SpeechTranscriber (iOS 26)

**Session:** WWDC25 277 "Bring advanced speech-to-text to your app with
SpeechAnalyzer" — https://developer.apple.com/videos/play/wwdc2025/277/
**Sample code:** "Bringing advanced speech-to-text capabilities to your app" —
https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app

### Architecture (iOS 26.0+ / macOS 26.0+)
- `SpeechAnalyzer` (actor) owns the session and routes audio to plug-in
  modules; input/output/control are decoupled async sequences; operations are
  scheduled by sample-accurate timecodes.
  https://developer.apple.com/documentation/speech/speechanalyzer
- Modules: **`SpeechTranscriber`** (the new long-form model powering
  Notes/Voice Memos/Journal), **`DictationTranscriber`** (system-dictation
  models, "compatible with older devices," ≈ on-device `SFSpeechRecognizer`),
  **`SpeechDetector`** (VAD gating transcription during silence; recommended
  `SensitivityLevel` `.medium`; runs alongside a transcriber).
- Input: `AsyncStream<AnalyzerInput>.makeStream()` →
  `analyzer.start(inputSequence:)` (autonomous) or `analyzeSequence(_:)`
  (file-style). Required format via
  `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`; convert each tap
  buffer before yielding (`BufferConverter` is a *sample-code helper* wrapping
  `AVAudioConverter`, not a framework type).
- **Volatile vs finalized:** opt in with `reportingOptions: [.volatileResults]`.
  Volatile results are immediate rough guesses, later **replaced** by one
  finalized result for that audio range (`result.isFinal`). Finalization is
  autonomous by default (observe `analyzer.volatileRange`), or forced:
  `finalize(through:)`, `finalizeAndFinishThroughEndOfInput()`,
  `cancelAndFinishNow()`. `prepareToAnalyze(in:)` preheats models.
  → Maps ~1:1 onto our provisional-replace pipeline: volatile → provisional
  commit; finalized → refined-echo replace; API-native settle signal.
- **Timing:** with `attributeOptions: [.audioTimeRange]` every
  `AttributedString` run carries `audioTimeRange: CMTimeRange` —
  sample-accurate text↔audio alignment (audit-grade timestamps).
- **Presets** (`SpeechTranscriber.Preset`): `.transcription`,
  `.progressiveTranscription`, `.timeIndexedProgressiveTranscription`, etc.
  (progressive = volatile + fast results). Compose manually via
  `TranscriptionOption` / `ReportingOption` / `ResultAttributeOption`.
- **Assets:** models live in system storage (shared across apps, auto-updated,
  zero app-size cost). Flow: `SpeechTranscriber.supportedLocales` /
  `installedLocales` → `AssetInventory.assetInstallationRequest(supporting:)` →
  `downloadAndInstall()` (has `progress`); locale reservations via
  `reserve(locale:)`. **This is a network download from Apple's servers** —
  must ride our operator-gated download policy; fully offline afterward.
  https://developer.apple.com/documentation/speech/assetinventory

### Custom vocabulary — the load-bearing fact
- **`SpeechTranscriber` supports NO contextual strings and NO custom language
  models.** Apple engineer (Sep 2025): `DictationTranscriber` supports this via
  `AnalysisContext.contextualStrings` on `SpeechAnalyzer.context`;
  `SpeechTranscriber` does not. — https://developer.apple.com/forums/thread/801877
- **`DictationTranscriber` supports both:** `AnalysisContext.contextualStrings`
  (https://developer.apple.com/documentation/speech/analysiscontext) and iOS 17
  custom LMs via
  `DictationTranscriber.ContentHint.customizedLanguage(modelConfiguration:)`.
  Other hints: `.shortForm`, `.farField`, `.atypicalSpeech`.

### Availability & positioning
- **Not Apple Intelligence-gated.** `SpeechTranscriber.isAvailable == false` on
  A13 (iPhone 11/SE2); works iPhone 12→17 **[community]**
  https://developer.apple.com/forums/thread/806765
- ~10 languages / ~34 locale variants at launch; enumerate `supportedLocales`
  at runtime **[community]**.
- Apple positioning: "faster and more flexible… good for long-form and distant
  audio." **[Third-party]** MacStories measured a 34-min episode in 0:45 vs
  1:41 for Whisper Large V3 Turbo, comparable quality —
  https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/

## 2. Maximizing SFSpeechRecognizer (iOS 17–25 path)

- `contextualStrings: [String]` (iOS 10+): "phrases that should be recognized
  even if they are not in the system vocabulary." Apple limits: **1–2 words per
  phrase, ≤100 phrases.**
  https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings
- **Custom LM pipeline** (iOS 17+, WWDC23 10101 "Customize on-device speech
  recognition" — https://developer.apple.com/videos/play/wwdc2023/10101/):
  1. `SFCustomLanguageModelData(locale:identifier:version:)` result-builder:
     `PhraseCount(phrase:count:)` (count = weight; balance against the overall
     data budget), `TemplatePhraseCountGenerator` (chess demo generated 10,000
     samples from one template — ideal for "BP <n> over <n>"), and
     `CustomPronunciation` (grapheme → **X-SAMPA**; per-locale symbols via
     `supportedPhonemes(locale:)`). `export(to:)` → `.bin` asset.
     https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata
  2. On device: `SFSpeechLanguageModel.prepareCustomLanguageModel(for:clientIdentifier:configuration:)`
     — "large amount of associated latency… call off the main thread."
  3. Per request: `request.customizedLanguageModel = .init(languageModel:vocabulary:)`;
     **`requiresOnDeviceRecognition = true` is mandatory** or requests silently
     run uncustomized. Customization data never leaves the device.
- Hints: `taskHint = .dictation` (continuous speech), `addsPunctuation`
  (iOS 16+).

## 3. Capture DSP for ASR input

- **Apple's canonical ASR config** (SpokenWord sample "Recognizing speech in
  live audio"): `setCategory(.record, mode: .measurement, options: .duckOthers)`,
  tap 1024 frames at input native format, partials on, on-device on.
  https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio
- `.measurement`: minimizes system-supplied processing; primary mic; lower
  levels — you own gain.
- `.voiceChat`: VoIP-tuned; **without** Voice I/O, echo cancellation and
  automatic gain correction are NOT applied.
- `inputNode.setVoiceProcessingEnabled(true)` (iOS 13+) = Apple's comms stack
  (WWDC23 10235): "echo cancellation, noise suppression, automatic gain
  control," per-device tuned; documented **for VoIP** — Apple's ASR samples do
  not enable it. Side effects: engine reconfiguration
  (`AVAudioEngineConfigurationChange` — observe and restart; input format can
  change) **[community + AudioKit #2606]**; reduced levels **[Apple forums]**;
  other-audio ducking on by default (tune via
  `voiceProcessingOtherAudioDuckingConfiguration`, iOS 17+). AGC alone:
  `isVoiceProcessingAGCEnabled` (default true). Also `isVoiceProcessingBypassed`,
  `setMutedSpeechActivityEventListener` (iOS 17+).
- **Verdict for a solo-speaker recorder with no playback path:** AEC is dead
  weight; NS can smear consonants in field noise. Apple's guidance points to
  `.measurement` + software gain for ASR. A/B before believing either way.
- Hardware input gain: `setInputGain` only after `isInputGainSettable` —
  route-dependent, never assume for built-in mics.
- **Software AGC: no Apple guidance exists.** Industry practice **[not
  Apple-sourced]**: high-pass ~80–100 Hz, slow RMS normalization toward ≈ −16
  to −20 LUFS equivalent, lookahead peak limiter, never clip; skip pre-emphasis
  (neural ASR doesn't need it). SpeechTranscriber is trained for distant audio
  — aggressive preprocessing buys less on iOS 26 than on SFSpeechRecognizer.
- **Built-in mic directivity:** `AVAudioSessionDataSourceDescription`
  `supportedPolarPatterns` / `setPreferredPolarPattern` per data source
  (Bottom/Front/Back), patterns `.omnidirectional`, `.cardioid`, `.subcardioid`
  (+ `.stereo` iOS 14+). `.cardioid` on the bottom/back source aims a beam —
  worth a chest-rig field test. Optional-typed; silent fallback.
  `setPreferredInputOrientation` matters only for `.stereo`.

## 4. External USB microphones (USB-C iPhones)

- USB Audio Class devices appear in `availableInputs` as
  `portType == .usbAudio`; iPhone 15+ connect directly (no MFi for UAC).
  Select via `setPreferredInput(_:)`; QA1799 "AVAudioSession — Microphone
  Selection" — https://developer.apple.com/library/archive/qa/qa1799/_index.html
- Multichannel: `setPreferredInputNumberOfChannels` up to
  `maximumInputNumberOfChannels`, **only after** category+mode+activation;
  confirm via `inputNumberOfChannels`.
- Sample rate follows the accessory (`setPreferredSampleRate` + read back);
  keep a converter stage.
- Power: iPhone 15+ USB-C supplies up to **4.5 W** to accessories
  (https://support.apple.com/en-us/105099); charge-while-recording needs a PD
  passthrough dock **[accessory practice]**. Pure wired UAC — RF Ghost clean.
- **[community]** iOS 26 input-routing regression reports: external USB mics
  enumerate but built-in stays selected; workarounds are the new
  Settings → Sounds & Haptics → Input picker or programmatic
  `setPreferredInput` — https://discussions.apple.com/thread/256226167

## 5. ReSpeaker 4-mic array verdict (hardware research)

- The 4-mic + onboard-DSP USB units are the **XMOS XVF-3000** family
  (ReSpeaker Mic Array v2.0 / USB Mic Array / USB 4-Mic Array v3.0; UAC 1.0
  driverless) and the newer **XVF3800** (UAC 2.0, USB-C). The "4-Mic Array for
  Raspberry Pi" is an I2S HAT — no USB, cannot connect to a phone.
  https://wiki.seeedstudio.com/ReSpeaker_Mic_Array_v2.0/
- All DSP runs on-chip (AEC, beamforming, de-reverb, NS, AGC, DOA, VAD);
  firmware variants: 1-ch processed vs 6-ch (ch0 processed, ch1–4 raw, ch5
  loopback); fixed 16 kHz; ~170–180 mA bus power (within iPhone's 4.5 W).
  https://github.com/respeaker/usb_4_mic_array
- iOS talks UAC only: **no LED ring, no DOA readout, no tuning** from iPhone
  (vendor USB control transfers require libusb — not available on iOS).
  Firmware must be flashed from a Mac/PC beforehand. No documented
  ReSpeaker-on-iOS precedent (untested territory, not known-broken).
- **Verdict: bench/desk instrumentation, not field hardware.** Far-field 360°
  conference array vs a near-field (~30 cm) chest-mounted single-talker
  problem; rigid 70 mm disc + tether = snag hazard; occupies the only port.
  Bench value is real: 6-ch firmware is a ready-made A/B rig (processed vs raw
  vs iPhone built-in over identical scripted playback). First step is a
  10-minute enumeration test via a USB-A→C data cable + the WS-2 route picker.

## 6. Recommendations (priority order, as adopted by the sprint spec)

1. **Custom LM on both OS generations** — `SFCustomLanguageModelData`
   (PhraseCounts + vitals templates + X-SAMPA pronunciations for
   tranexamic acid/Hextend/cric) → `prepareCustomLanguageModel` +
   `customizedLanguageModel` on iOS 17–25; same configuration via
   `DictationTranscriber.ContentHint.customizedLanguage` on iOS 26. **(M)**
2. **`contextualStrings` today** — ≤100 short rubric-derived phrases. **(S)**
3. **Availability-gated SpeechAnalyzer backend** — volatile/finalized maps to
   provisional-replace; `audioTimeRange` audit timestamps; bake off
   SpeechTranscriber (no vocab) vs customized dictation path; WER decides. **(M–L)**
4. **A/B capture DSP** — VP-AGC vs `.measurement` + software conditioner. **(S–M)**
5. `taskHint = .dictation`, deliberate `addsPunctuation`. **(S)**
6. `.cardioid` on bottom/back data source — chest-mount field test. **(S)**
7. `SpeechDetector` VAD on the iOS 26 lane. **(S)**
8. USB `.usbAudio` route surfacing in Settings. **(S–M)**
