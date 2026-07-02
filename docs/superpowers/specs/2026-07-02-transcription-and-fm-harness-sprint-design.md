# Sprint Design — Transcription Quality + Apple FM Agentic Harness

**Date:** 2026-07-02
**Status:** DRAFT — awaiting operator review
**Companion research (committed alongside):**
- `docs/research/2026-07-02-apple-speech-stack-research.md` (SpeechAnalyzer, custom LM, capture DSP, USB audio, ReSpeaker)
- `docs/research/2026-07-02-apple-fm-agentic-research.md` (Foundation Models framework, guided generation, tools, guardrails)

---

## 0. Scope statement (read this first)

**This is a WIDE sprint** — the widest since the event-sourcing cycle. It contains
five workstreams sized for roughly **3–5 focused sessions**, sequenced so each
lands independently and each is device-validated before the next starts. It is
*not* a single-session spec. The unifying thesis:

> Transcription accuracy is currently unmeasured and unbiased toward TCCC
> vocabulary; the LLM lane is freeform-string in/out. This sprint (1) builds the
> measurement harness that makes every audio claim testable, (2) attacks the
> exact known failure mode — domain terms like "tranexamic acid" — with the
> strongest levers Apple offers, and (3) converts the Apple FM backend from a
> text-completion endpoint into a structured, evidence-gated candidate producer:
> the first real increment of the agentic harness on the validated default lane.

What this sprint is **not**: it does not touch Parakeet/Granite/LFM2/Qwen
(experimental lanes stay as-is), does not build the deterministic
workflow-obligation engine (next cycle; see §10), does not integrate ReSpeaker
hardware into the app (bench instrumentation only), and does not flip any
validated default without benchmark evidence.

---

## 1. Where we are (recon findings, 2026-07-02)

Audio capture (`TCCC_IOS/Audio/SpeechRecognizer.swift`):
- Session config is **internally contradictory**: `.playAndRecord` + `.measurement`
  (minimizes system DSP) *plus* `setVoiceProcessingEnabled(true)` +
  `isVoiceProcessingAGCEnabled = true` (the VoIP comms stack: AEC+NS+AGC) at
  `SpeechRecognizer.swift:123-128, 368-372`. The VP enable is a silent
  best-effort `do/catch` — if it throws we capture at hardware unity and never
  know. Apple's own ASR samples use `.record` + `.measurement` **without** voice
  processing; VP is documented for VoIP, with known level reduction.
- **Zero vocabulary biasing** on the default lane: no `contextualStrings`, no
  `taskHint`, no `addsPunctuation`, no custom language model (grep-verified).
  The only biasing in the codebase is a Granite prompt keyword string.
- Manual gain trim exists (Settings slider → `gainProvider` multiply at
  `:283-286`); RMS metering exists (`:417`). No software AGC, no high-pass, no
  limiter. No route/input selection anywhere (`preferredInput` grep: zero hits)
  — a USB mic would be auto-selected by iOS or not at all; nothing surfaces it.
- Provisional-replace pipeline (`App/AppState.swift:539-697`): 2.0 s timer
  settle window; refined recognizer echo replaces provisional in place.

LLM lane (`Intelligence/`):
- `AppleFoundationLLMBackend.swift:44-52` is `LanguageModelSession(instructions:)`
  + `respond(to:)` → plain string. **No `@Generable`, no `Tool`, no structured
  decoding.** Generators parse/validate strings and fall back deterministically
  above a 40 % rewrite threshold (`RadioScriptGenerator.swift:77-100`,
  `ZMISTNarrativeGenerator.swift:44-85`). `EncounterNarrativeGenerator` has **no
  validator and no fallback** — the one unguarded LLM output.
- The reconciliation structure already exists and is proven: hot-seat review
  queue → operator-gated accept → contradiction check → `FieldRouter` →
  `engine.recordOperatorAcceptedFact` (`GraniteReviewQueue.swift:24-117`). It is
  wired only to the experimental Granite lane; the validated Apple FM default
  has no candidate-producer role at all.

Benchmarking:
- `DevTools/GraniteAudioBenchmarkRunner.swift` is hardwired to
  `GraniteSpeechRuntime`, computes **keyword recall only** (20 fixture tokens,
  `:443-448`) — no WER, no extraction scoring, can't touch the Apple lane.
- **Ground truth for `Valdez Alley.m4a` is located**: it is the TTS rendering of
  the 5-Minute Narrative fixture, verbatim at
  `docs/specs/v1_initial_greenfield.md:399-409`, with an expected-extraction
  acceptance baseline at `:411-414`. Known audio defect: the TTS voice garbles
  "TXA"/"tranexamic acid" (operator-reported); the benchmark treats that line as
  a documented reference defect, not an ASR error.

Hygiene:
- **No build-identity stamp exists** (static `CFBundleShortVersionString: 1.0`,
  no build-phase scripts, no About/version row) — violates the standing global
  rule. Stale docstrings in `SpeechRecognizer.swift` say "~10 s" ring buffer;
  code says 30 s (`:33`).

Vision alignment (distilled from `Building-an-Agentic-Harness.md` + audio sprint
docs V1–V3 on the operator's desk): the event ledger, durable persistence, and
provenance work shipped in June already satisfy the harness doc's diagnoses
#1–#4. What remains, in its own priority language: the reconciliation/candidate
lane on the default brain, artifact pipelines with validators everywhere, the
evaluation harness ("100–300 synthetic sequences, not four fixtures" — this
sprint builds the *instrument*; corpus growth is incremental), and — explicitly
next cycle, not this one — the deterministic workflow-obligation engine with a
typed action protocol. Doctrine carried forward verbatim: *"A model inference
must never silently become a patient fact."*

---

## 2. Goals / non-goals

**Goals**
1. Every transcription claim becomes measurable on-device: WER + keyword recall
   + extraction-field accuracy + latency + memory, against the Valdez fixture,
   for any `TranscriptStream` backend.
2. Domain-term accuracy materially improves on the Apple default lane
   (custom LM + contextual strings + task hints).
3. The capture chain has *deliberate*, A/B-validated gain handling — either
   Apple's VP-AGC or our own measurement-mode software AGC, chosen by data.
4. iOS 26's `SpeechAnalyzer`/`SpeechTranscriber` is available as an
   operator-selectable backend, benchmarked against the customized dictation
   path; a default flip happens only on benchmark evidence.
5. Apple FM becomes a structured candidate producer feeding the existing
   review-queue → validator → engine apply path, with guided generation
   replacing freeform strings in all three report generators.
6. Build identity is stamped and visible in-app (standing rule).

**Non-goals**
- No workflow-obligation engine / typed action protocol (next cycle).
- No multi-casualty UI, no §C tap-to-edit (separate backlog items).
- No Granite/Parakeet/LFM2/Qwen changes beyond compile compatibility.
- No ReSpeaker app integration (bench rig only; see research memo §ReSpeaker).
- No custom FM adapters (requires Developer Program entitlement; SideStore
  distribution rules it out — research memo §5).
- No default-flip of ASR or LLM backends without benchmark evidence.

---

## 3. Workstream 0 — Build stamp + hygiene (S, first commit of the sprint)

1. `project.yml` build-phase script generates `BuildStamp.swift` (or stamps
   Info.plist keys): semantic version, git short SHA, branch, build date.
2. Surface it in `SettingsOverlay` as a static "About" row:
   `v1.0 (a1b2c3d) main · 2026-07-02`. Visible on every install thereafter.
3. Fix stale docstrings (`SpeechRecognizer.swift` header + `:48` — 30 s, not
   10 s). Zero behavior change.

Acceptance: fresh device install shows the stamp; `git log` SHA matches.

---## 4. Workstream 1 — Transcription benchmark harness (M, the truth engine)

**Everything else in this sprint is gated on this landing first.**

### 4.1 Reference fixture
- Promote the 5-Minute Narrative to a canonical fixture:
  `TCCC_IOS/DevTools/Fixtures/valdez_alley_reference.txt` (verbatim from
  `v1_initial_greenfield.md:399-409`, timestamps stripped) + a sidecar
  `valdez_alley_reference.json`: token-normalization exceptions, the
  known-defect list (TXA pronunciation), and the 20-token keyword list —
  **flagged as fixture-overfitted** (contains Dawson/Reaper/NKDA); keyword
  recall stays a secondary metric only.
- `Valdez Alley.m4a` is copied into `Documents/TranscriptionBenchmark/fixtures/`
  on the device via Files.app / `devicectl copy` (same pattern as the Granite
  runner; audio binaries stay out of git).

### 4.2 Scorer (TCCCKit — pure, unit-tested)
- New `TCCCBench` module in `Packages/TCCCKit`: `WERScorer` (Levenshtein over
  normalized tokens; substitutions/insertions/deletions reported separately),
  `TokenNormalizer` (lowercase, strip punctuation, numeral↔word folding table,
  domain folds: "t x a"→"txa", "nine line"→"9-line"), `KeywordRecallScorer`
  (existing token-list semantics), and `ExtractionScorer` (field-level
  precision/recall of engine output vs the `:411-414` acceptance baseline —
  ties ASR quality to the DD1380 deliverable, which is the point).
- Port assertions for the normalizer/WER from hand-computed cases; property
  test: WER(x,x)==0, WER symmetric bounds.

### 4.3 Runner (app target, DevTools)
- Generalize the benchmark entry point: `--transcription-benchmark` launch arg
  runs any registered `TranscriptStream` backend over the fixtures folder in
  **file-ingestion mode**: decode the m4a with `AVAudioFile`, push buffers
  through the same ingest path the mic uses (tap bypass), collect the final
  committed transcript from the provisional-replace pipeline, score, and write
  `Documents/TranscriptionBenchmark/results/<backend>-<stamp>.json` +
  a one-screen summary view.
- Metrics per run: WER, keyword recall, extraction P/R, first-partial latency,
  settle latency, peak `phys_footprint`.
- **Acoustic replay mode** (secondary, for DSP A/Bs that only exist at the mic):
  documented operator procedure — phone on desk at fixed distance/volume, Mac
  plays `Valdez Alley.m4a` from speakers, run captures via the real mic path.
  Results carry a `mode: acoustic` tag; only compare acoustic-to-acoustic.
- The existing Granite runner keeps working; it may later delegate to the
  generalized runner (not required this sprint).

Acceptance: baseline numbers exist for the **current** default lane (both
modes), committed to `docs/research/` as the sprint's before-picture, before
any WS-2/WS-3 change merges.

---

## 5. Workstream 2 — Deliberate capture DSP (M)

### 5.1 The A/B (decides the default capture config)
Two configurations, acoustic replay mode, three runs each:
- **Arm A (current)**: `.measurement` + VP enabled + VP-AGC on.
- **Arm B**: `.measurement`, **no voice processing**, new software chain:
  high-pass biquad (~90 Hz) → RMS tracker (300 ms window) → makeup gain toward
  −20 dBFS RMS target (attack ~100 ms, release ~1 s, clamp [0.5×, 8×]) → hard
  peak limiter (−1 dBFS). Implemented as a `GainConditioner` stage in
  `ingestBuffer` where the manual multiply lives today (`:283-286`); manual
  Settings slider becomes a bias on top; applied-gain value streams to the
  dev HUD next to the existing RMS meter.
- Ship the WER winner as default; the loser stays behind a Settings debug
  toggle (`Capture DSP: Voice-Processing / Conditioned Raw`) for field re-tests.
- Rationale for suspicion of Arm A: VP is the VoIP stack — AEC is dead weight
  with no playback path, NS can smear consonants in exactly the ambient noise
  that matters, level reduction is documented, and the `.measurement` pairing
  is unsupported territory. But the data decides, not the doctrine.

### 5.2 Route + directivity (S each, optional-guarded)
- Surface `availableInputs` in Settings (read-only list + `setPreferredInput`
  picker). Enables wired USB-C lav mics and the ReSpeaker bench rig; `.usbAudio`
  is pure wired UAC — RF Ghost clean. Route changes already append a system
  transcript line via `AudioSessionCoordinator`.
- Behind a debug flag: try `.cardioid` polar pattern on the back/bottom built-in
  data source (`setPreferredDataSource` + `setPreferredPolarPattern`) — a
  chest-mounted phone pointing a beam at the medic's mouth. All optional-typed;
  silent fallback when unsupported. Field-test flag only this sprint.
- Fix the VP-enable silent catch: log + surface the actual capture config in
  the dev HUD so "which DSP am I running?" is answerable on any build.

Acceptance: A/B table committed; default capture config chosen by WER; capture
config visible at runtime; USB input selectable and persisted.

---

## 6. Workstream 3 — Vocabulary + the iOS 26 speech stack (L)

### 6.1 Contextual strings + hints (S — do first, immediate win)
- Derive ≤100 short phrases (1–2 words: drug names, "needle decompression",
  "chest seal", "battle roster"…) at runtime from
  `reference/rubric/extracted/march_paws_vocabulary_2026.json` — single source
  of truth, **no fixture-specific proper nouns** (no Dawson/Reaper; that
  over-fits the benchmark). Set on every `SFSpeechAudioBufferRecognitionRequest`
  (`contextualStrings`), plus `taskHint = .dictation`; make `addsPunctuation`
  an explicit decision (default on) rather than an unset default.

### 6.2 Custom language model (M — the big domain lever, iOS 17+)
- New repo tool `Tools/TCCCCustomLM/` (macOS SPM executable):
  `SFCustomLanguageModelData` built from the rubric JSON — `PhraseCount`s for
  MARCH/PAWS vocabulary, `TemplatePhraseCountGenerator` templates for vitals
  grammar ("BP <n> over <n>", "heart rate <n>", "SpO2 <n> percent", MGRS digit
  strings), and `CustomPronunciation` (X-SAMPA) for the known hard terms:
  *tranexamic acid, Hextend, cricothyroidotomy, hemostatic, moxifloxacin,
  ertapenem* — exactly the "tranexamic acid" failure the operator flagged.
  Output `TCCC_en_US.bin` committed as a bundled resource (no network, RF-Ghost
  clean).
- App side: `prepareCustomLanguageModel` off-main at launch (Apple warns it's
  slow; hide behind the existing model-status UI), then
  `request.customizedLanguageModel = …` on the default lane.
  `requiresOnDeviceRecognition = true` is already set — mandatory for custom LM.

### 6.3 SpeechAnalyzer backend (M–L, iOS 26+, operator-selectable)
- New `SpeechAnalyzerTranscriptStream: TranscriptStream` (availability-gated
  `#available(iOS 26, *)`; device support iPhone 12+):
  - `SpeechTranscriber` module, volatile results + `.audioTimeRange` attributes;
    **volatile → existing provisional commit; finalized → existing refined-echo
    replace.** The API's autonomous finalization becomes the settle signal for
    this lane (the 2.0 s timer remains for the SFSpeech lane) — a cleaner,
    model-driven settle than wall-clock.
  - `SpeechDetector` VAD in front (long encounters stop paying for silence).
  - `AssetInventory` model download wired into the **existing operator-gated
    download flow** (it is a network fetch from Apple — same policy shelf as
    Parakeet/Granite downloads; transcription is fully offline after install).
- Fourth entry in the Settings ASR picker: "Apple SpeechAnalyzer (iOS 26)".
- **Bake-off, benchmark-gated default flip**: SpeechTranscriber **cannot take
  contextual strings or custom LMs** (Apple-confirmed); `DictationTranscriber`
  can (same custom-LM configuration via `ContentHint.customizedLanguage`). So
  the candidates are: (a) SFSpeech + custom LM (6.2), (b) SpeechTranscriber
  raw (better base model, no vocabulary), and optionally (c)
  `DictationTranscriber` + custom LM under the new API. WER + extraction P/R on
  the harness decides the iOS 26 default; the decision and numbers go in the
  sprint log. No flip without data.

Acceptance: measurable WER/extraction delta vs the WS-1 baseline for 6.1 and
6.2 — concretely: the tracked domain-term set (tranexamic/TXA, Hextend, needle
decompression, chest seal, AVPU, SpO2, NKDA, battle roster) has strictly fewer
substitution errors than baseline with overall WER no worse (stretch: −20 %
relative WER); SpeechAnalyzer lane runs the full Valdez fixture on-device
without regression to the default lane.

---

## 7. Workstream 4 — Apple FM structured candidate lane (L)

Converts the validated default LLM from text-completion to the harness's first
real brain, per the FM research memo's recommended shape. Doctrine: *the model
proposes, deterministic code disposes* — unchanged, now structurally enforced
end-to-end.

### 7.1 Micro-session client (no long-lived agent)
- `Intelligence/AppleFMStructuredClient.swift`: fresh `LanguageModelSession`
  per request from a **prewarmed template** (static instructions +
  `prewarm(promptPrefix:)` after each request → sub-second TTFT), greedy
  sampling, one shared error adapter mapping `GenerationError` cases
  (`exceededContextWindowSize` → digest-only retry once → fallback;
  `guardrailViolation`/`refusal` → deterministic fallback + dev-mode feedback
  log; `concurrentRequests` → actor-serialized; `assetsUnavailable` → status
  badge). Context budget asserted by character heuristic (~3.5 chars/token;
  device is on 26.2 — `tokenCount(for:)` arrives with 26.4).
- ASR text is **untrusted input and never enters `instructions`** — prompts
  only (prompt-injection posture, consistent with the ledger's existing
  injection flagging).

### 7.2 Extraction/reconciliation lane (the agentic increment)
- `AppleFMReconciliationService`: on each settled batch (starting values: 5
  settled lines or a 20 s window, whichever first; foreground only; tune in
  the plan), build a **deterministic state digest**
  (~300 tokens: MARCH phase statuses, latest vitals row, open interventions,
  unfilled DD1380 fields — rendered from `PatientStateEngine.deterministicFacts`
  with stable ordering) + the new settled lines, then
  `respond(generating: FMCandidatePatch.self)`.
- `@Generable struct FMCandidatePatch`: typed proposals (vitals with
  `@Guide(.range)` physiologic bounds; interventions/findings as **enums
  generated from the rubric JSON** — constrained decoding makes out-of-vocabulary
  field names impossible); every proposal carries
  `@Guide("verbatim supporting words") evidence: String`.
- Validator gate (deterministic, before anything reaches the operator):
  evidence must fuzzy-substring-match the source chunk (anti-fabrication),
  physiologic plausibility via existing TCCCReports validators, idempotence vs
  current state. Survivors land in the **existing review queue** — generalize
  the `GraniteReviewQueue` plumbing to a backend-tagged `ReviewQueue` (Granite
  stays a producer; the operator-gated accept → contradiction check →
  `FieldRouter` → engine path is reused verbatim). Engine remains sole writer;
  `EngineInvariantTests` extended to cover the new service.
- **No tools in the extraction lane** — deliberate: Apple guidance says inline
  what the model always needs, and community testing shows root-level guided
  generation suppresses tool use. Digest-inline is the design, not a shortcut.
  (A 2-tool read-only diagnostic lane — vitals trend, event tail — is a stretch
  goal, only if 7.1–7.3 land early.)

### 7.3 Guided generation for the three report generators (M)
- When backend == Apple FM: Radio script, ZMIST narrative, and encounter
  narrative generate into `@Generable` structures (e.g. nine typed MEDEVAC
  lines) instead of freeform strings; existing `MedevacValidator`/
  `ZMISTValidator` + 40 % drift fallback stay as the outer gate (belt and
  suspenders — schema guarantees shape, validators guarantee content).
- **Close the narrative gap**: `EncounterNarrativeGenerator` gets a validator
  (length + claims-vs-state check) and a deterministic template fallback — no
  more unguarded LLM output anywhere in the app.
- Other backends keep the string path unchanged.

### 7.4 Guardrail reality check (bundled into 7.2 validation)
- Run the Valdez fixture + the three Python scenario texts through the
  extraction lane on-device; count `guardrailViolation`/`refusal` on clinical
  trauma narration (research flags violence-adjacent false positives; iOS 26.4
  reduced them; clinical register in instructions mitigates). If refusal rate
  on realistic narration exceeds ~10 %, the extraction lane ships dev-flagged
  only and the finding goes in the sprint log with `logFeedbackAttachment`
  captures. Deterministic extractors remain the floor either way — the app
  never gets worse than today.
- Acceptable-use note (for the record): Apple prohibits unsupervised
  consequential medical decisions; this architecture is
  proposal → validator → operator confirm → engine, i.e., human supervision by
  construction. Documented in code comments at the service boundary.

Acceptance: FM proposals appear in the review queue with evidence strings on
device; zero writes to `PatientState` outside engine methods (structural test);
guided-generation reports pass validators with drift below the fallback
threshold on the fixture scenarios; narrative generator has a fallback.

---

## 8. Execution order & session sizing

| Phase | Contents | Size |
|---|---|---|
| 0 | WS-0 build stamp + hygiene | S (first commits) |
| 1 | WS-1 harness + **baseline numbers committed** | 1 session |
| 2 | WS-2 DSP A/B + route/directivity; WS-3.1 contextual strings (S, rides along) | 1 session |
| 3 | WS-3.2 custom LM + WS-3.3 SpeechAnalyzer backend + bake-off | 1–1.5 sessions |
| 4 | WS-4 FM structured lane + generator upgrade + guardrail check | 1–1.5 sessions |

Rules: benchmark before/after for every phase; device validation gates each
merge (per repo convention); any `BLOCKED:` beats partial delivery; each phase
is independently shippable — if the sprint stops after any phase, main is
healthier than before it.

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Acoustic replay is room-dependent → noisy A/B | Fixed geometry procedure + 3 runs/arm + file-ingestion mode for anything not mic-bound |
| Custom LM prepare latency at launch | Off-main + status UI (Apple-documented pattern); prepared-state cached |
| SpeechTranscriber wins base WER but loses domain terms | That's exactly what the bake-off measures; extraction P/R (not raw WER) is the primary decision metric |
| FM guardrails refuse trauma narration | Measured explicitly (7.4); deterministic floor unchanged; dev-flag ship option |
| 4,096-token ceiling | Stateless micro-sessions + ~1,850-token budget/request (research memo budget table); no accumulation by design |
| VP removal exposes clipping in loud environments | Limiter in the software chain; loser config stays operator-switchable |
| Scope creep into workflow engine | Explicit non-goal; typed action protocol deferred to next cycle |

## 10. Explicitly deferred (next cycles)

Deterministic workflow-obligation engine + typed model-action protocol
(`ASK_ONE_QUESTION` / `SET_TIMER` / …, per the harness doc §4–5) and the
attention UI; synthetic evaluation corpus growth to 100–300 sequences (the
harness built here is its instrument); multi-casualty UI; §C tap-to-edit;
engine-on-partial-text experiment; settle-window tuning (subsumed by the
SpeechAnalyzer finalization model if that lane wins); alt-backend WER passes
(same harness, later); ReSpeaker bench A/B write-up.

## 11. Alternatives considered

- **One long-lived FM agent session with tools** — rejected: 4,096-token
  ceiling makes a 30-min encounter impossible; Apple's own guidance is many
  small requests orchestrated by deterministic code; tool-calling reliability
  on the 3B model is the weakest link and guided generation suppresses it.
- **Custom FM LoRA adapter for TCCC vocabulary** — rejected: requires a
  Developer Program entitlement (SideStore rules it out), retrains every OS
  model update, and Apple says exhaust prompting/tools first.
- **Granite/Parakeet as the vocabulary answer** — out of scope by operator
  direction (Apple lane is the sprint focus); their keyword-prompt biasing
  stays available on the experimental lanes.
- **ReSpeaker as field hardware** — rejected for scope: far-field conference
  array vs near-field chest-mount mismatch; no iOS control channel (UAC audio
  only); port occupancy + snag hazard. Retained as bench instrumentation via
  the WS-2 route picker.
- **Skipping the benchmark and tuning by ear** — rejected: it's how the AGC
  contradiction shipped in the first place.
