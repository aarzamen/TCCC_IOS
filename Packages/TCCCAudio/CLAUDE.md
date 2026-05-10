# TCCCAudio (Sprint 1 — Granite Speech Foundation)

Local shim package bringing `Blaizzy/mlx-audio-swift` into the app
target with the heavy MLX deps isolated here, not in `Packages/TCCCKit`
(pure logic) and not in the app target (AGENTS.md "no logic in app
target"). Mirrors the existing `Packages/TCCCLLM` shim pattern.

## Pinned versions

| Dep | Version | SHA |
|---|---|---|
| `mlx-audio-swift` | v0.1.2 | `fcbd04daa1bfebe881932f630af2ba6ce9af3274` |

Resolved via `git ls-remote https://github.com/Blaizzy/mlx-audio-swift refs/tags/v0.1.2`.

## Resolver-conflict notes (G0)

v3 §G0 anticipated a conflict between this package's `mlx-swift-lm` ≥ 3.x
need and `Packages/TCCCLLM`'s `from: "2.25.5"`. **The conflict did not
fire** — mlx-audio-swift v0.1.2 actually declares
`.upToNextMajor(from: "2.30.3")` on `mlx-swift-lm`, which means
`>= 2.30.3, < 3.0.0`. That intersects cleanly with TCCCLLM's
`from: "2.25.5"` (also `< 3.0.0`). The resolver picks whatever 2.x is
latest and both sides accept it. No Path A/B/C recovery needed.

## Sprint 1 phase journal

### G0 — Scaffolding (2026-05-10)

- Created `Packages/TCCCAudio/` mirroring `Packages/TCCCLLM/`.
- Pinned mlx-audio-swift to commit SHA, not a branch.
- Re-export `MLXAudioCore` + `MLXAudioSTT` only. `MLXAudioCodecs`,
  `MLXAudioVAD`, etc. are not needed for Sprint 1's ASR work.
- Did not touch `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift`
  body in G0 per v3 §G0 explicit constraint. G1 fills in the body.

### `swift test` from CLI: not the right harness

v3 §G0.6 lists `cd Packages/TCCC<X> && swift test` as part of
verification. It doesn't work for the MLX-dependent packages and
never has — both `TCCCLLM` and `TCCCAudio` declare `.iOS(.v17)` only,
but `swift test` defaults to the host (macOS), and the upstream
products require macOS 14:

```
error: the library 'TCCCAudio' requires macos 10.13, but depends on
the product 'MLXAudioCore' which requires macos 14.0; consider
changing the library 'TCCCAudio' to require macos 14.0 or later, or
the product 'MLXAudioCore' to require macos 10.13 or earlier.
```

`TCCCKit` is pure logic and `swift test` works there (724 tests
passing on host). For `TCCCLLM` and `TCCCAudio`, the canonical
verification is the xcodebuild simulator build (which passed cleanly
in G0) and `xcodebuild test` on the iPhone 17 Pro simulator (which
G1 will exercise once test targets land). Don't add `.macOS(.v14)`
to TCCCAudio just to make `swift test` quiet — it has no test target
yet, and once G1 lands tests, they'll run through the simulator the
same way TCCC_IOSTests does today.

### Destination-string note (matches `SPRINT_BOARD.yaml` precedent)

The v3 spec's verification command uses
`-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26'`. On
this machine that's ambiguous — both an iOS 26.3 and iOS 26.4
iPhone 17 Pro simulator are available, and `OS=26` matches neither
because xcodebuild expects an exact runtime version. The fix is to
pin by UUID, matching what Codex's earlier sprint already used in
`docs/granite/SPRINT_BOARD.yaml`:

```
-destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E'
```

That's the iOS 26.4 iPhone 17 Pro simulator. Use this form for all
autonomous self-verification builds. If the sim ID drifts on a fresh
machine, run `xcrun simctl list devices iPhone | grep "iPhone 17 Pro"`
to find the current ID.

### Loader API surface at the pinned SHA (note for G2)

At v0.1.2 (`fcbd04daa1bfebe881932f630af2ba6ce9af3274`),
`MLXAudioSTT.GraniteSpeechModel` exposes only one loader:

```swift
public static func fromPretrained(
    _ modelPath: String,        // HF repo ID, e.g. "mlx-community/granite-4.0-1b-speech-5bit"
    cache: HubCache = .default
) async throws -> GraniteSpeechModel
```

The loader internally calls `ModelUtils.resolveOrDownloadModel(repoID:requiredExtension:cache:)`.
A `fromModelDirectory(URL)` overload exists on `main` (line 1080) but
**was added after v0.1.2** — not available at our pin.

**Implication for G2:** the resolver seeds an `HubCache` whose root is
the user-picked Files.app folder. If the folder already contains an HF
snapshot layout (`models--<owner>--<repo>/snapshots/<rev>/...`),
`resolveOrDownloadModel` returns the existing path with no download.
This matches v3 §2's "Loader API contract" caveat exactly. Documented
here so G2 doesn't re-discover it.

### G1 — Multi-source resolver + bookmark store + policy tests (2026-05-10)

- `GraniteSpeechBookmarkStore.swift` — `Sendable` struct wrapping a
  persistent security-scoped bookmark in `UserDefaults` under
  `tccc.graniteSpeech.modelBookmarkV1`. `save / resolve / clear /
  hasBookmark`. Stale-on-resolve: opportunistically rebuilds the
  bookmark while a scope handle is briefly acquired, so the next
  resolve is fresh. Caller activates security scope after resolve.
- `GraniteSpeechModelResolver.swift` — `Sendable` struct with the
  three-source chain in v3 §2 priority order (bookmark → bundle → HF
  cache). HF cache lookup is injected as a `@Sendable (String) -> URL?`
  closure; the app target wires it to `HFHubCache.directory(for:)`,
  keeping TCCCAudio free of app-target dependencies. Throws
  `.modelNotProvided(modelID:)` if all three miss.
- `GraniteSpeechRuntime.swift` — actor with `prime() / unload() /
  primedURL / primedSource`. Holds the security scope for the
  lifetime of `state == .primed` only when the resolver returned a
  bookmark-source URL. Bundle and HF-cache URLs need no scope dance.
  Best-effort scope release in `deinit` if the actor is destroyed
  without an explicit `unload()`. **No model load yet — that's G2.**
- App-target wire: `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift`
  body replaced. `authorize / prime / unprime / stop / stopImmediate`
  delegate to the runtime; `start(audioURL:)` still throws
  `.transcribeNotYetImplemented` per v3 G1 — G2 fills it in.
- `AppState.ASRBackend.graniteSpeech.displayName`: "Granite Speech
  (research)" → "Granite Speech (alt)". Comment updated to match v3
  language ("alternate ASR; requires configured local Granite Speech
  model folder").
- `AppState` adds `graniteSpeechBookmarkStore` so SettingsOverlay
  and the runtime share a single bookmark instance via the same
  default UserDefaults key.
- `SettingsOverlay`: new `graniteSpeechModelFolderRow` shown only when
  `state.asrBackend == .graniteSpeech` (parallel to the existing
  Parakeet conditional). SwiftUI `.fileImporter` in `.folder` mode
  presents `UIDocumentPickerViewController` under the hood.
  Status pill: Active / Stale (re-select) / No model selected /
  Error. v3 §G1 stale-bookmark UX: the row surfaces the state via
  banner color + "Re-select Model Folder" button — picker does not
  auto-fire on RECORD.

### G1 — Test coverage

- `TCCC_IOSTests/GraniteSpeechTranscriptStreamTests.swift` rewritten:
  - `testGraniteSpeechIsExplicitAlternateASRBackend` — default ==
    `.appleSpeech`; `.graniteSpeech` is selectable but not first;
    `displayName == "Granite Speech (alt)"`.
  - `testGraniteSpeechResolverThrowsWithoutAnySource` — empty
    resolver throws `.modelNotProvided(modelID:)`. Mocks all three
    sources to return nil; no network calls (verified by mock).
  - `testBookmarkSaveResolveStaleClearLifecycle` — round-trip in
    UserDefaults with isolated key + temp-dir fixture.
  - `testGraniteSpeechTranscriptStreamAuthorizeThrowsBackendUnavailableWithoutSource`
    — TranscriptStream surface verified end-to-end against the
    placeholder resolver chain.
  - `testGraniteSpeechStartAlwaysThrowsInG1` — explicit guard
    against any UI path that might call `start(audioURL:)` before
    G2 lands.
  - `testGraniteSpeechPrimeWithConfiguredFolderOnSimulator` —
    env-gated via `GRANITE_SPEECH_MODEL_DIR`. Skipped by default;
    set the env var in the test scheme to exercise the real prime
    path on simulator.

Verification: 19 targeted tests passing on iPhone 17 Pro (iOS 26.4)
simulator (`id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E`), 1 skipped
(env-gated). Touch-and-feel of full TCCC_IOSTests via xcodebuild
test had a sim launch flake ("Application failed preflight checks /
Busy") — unrelated to G1 code; targeted regression run after sim
reset was clean.

### G2 — Real model load + transcribe on physical iPhone (2026-05-10)

- New `GraniteSpeechModelLoader.swift` mirrors `GraniteSpeechModel.fromPretrained`'s post-resolve body but takes a directory URL directly. Bypasses the upstream `ModelUtils.resolveOrDownloadModel` cache-path mangling (`<cacheDir>/mlx-audio/<owner>_<repo>/`) so the operator can pick a flat folder of `config.json + *.safetensors + tokenizer files` via the Files picker.
- New `MemoryMonitor.swift` (per v3 §7): `phys_footprint` from `task_vm_info`, `os_proc_available_memory()`, `mach_task_basic_info.resident_size`. Includes a SwiftUI-friendly `MemoryMonitorObserver` (1 Hz polling + system memory-pressure subscription) and a CSV logger for jetsam forensics.
- New `GraniteSpeechPrompt.swift` — keyword-biased ASR prompt sourced from v1 §6 acceptance baseline + the medications/interventions listed in `GraniteCandidatePatch`.
- `GraniteSpeechRuntime` now actually loads the model in `prime()` (timed; captures pre/post `phys_footprint` snapshots) and exposes `transcribe(audioURL:prompt:maxTokens:temperature:)` returning `AsyncThrowingStream<STTGeneration, Error>`.
- `Packages/TCCCAudio/Package.swift` adds explicit deps on `mlx-swift`, `mlx-swift-lm`, `swift-transformers` so the loader can `import MLX`, `import MLXNN`, `import Tokenizers` directly. (Previously these were only transitive through mlx-audio-swift.)

App-target additions:
- `TCCC_IOS/DevTools/GraniteBakeoffView.swift` (~280 lines) — bake-off harness. Resolves model via the shared bookmark store, primes, transcribes the bundled fixture, captures peak `phys_footprint`, computes keyword recall against the v1 §6 token list, appends a row to `Documents/BAKEOFF_RESULTS.md`.
- `DevToolsLandingView` adds a third "Bake-off" tile alongside Sender/Receiver.
- `DevToolsRootView` threads `state: AppState` through (so the bake-off can read the shared bookmark store) and adds a `.graniteBakeoff` route.
- `TCCC_IOS/Resources/test_5min.wav` — 14-s fixture, 16 kHz mono Float32 WAV. **The file name is historical — see "Long-form encoder caveat" below.** Generated via `say` + `afconvert` from the first paragraph of the v1 §6 narrative.

### G2 — Hardware validation results (iPhone 17 Pro, iOS 26.2)

Cold prime + transcribe of a 14-s fixture:
- Prime: **1.99 s**, `phys_footprint` Δ **+2196.3 MB** (matches the safetensors size; quantize step doesn't double-buffer).
- Post-load resident: 2.16 GB.
- Available headroom post-load: **3.84 GB** → total runtime cap **6.0 GB** (the `com.apple.developer.kernel.increased-memory-limit` entitlement is being honored on Apple Personal Team certificates — surprise upside; documented for future reference).
- Transcribe: **5.78 s for 14-s audio** = 2.4× real-time decode.
- Peak `phys_footprint` during transcribe: **2.46 GB** (only +250 MB above post-load).
- Warm-run prime time: **1.04 s** (Δ +49 MB only) — model weights stay page-cached across `unload()` → `prime()`.

Sample transcript (cold run):
```
break break this is medic kilo 6 i have a metavac request grid
co-ordinate 8734-9012-0 frequency 444.50 call sign reaper one
urgent surgical gsw to the chest
```

Recognized form is correct — keyword recall **6/20 (30%)**, expected because the test fixture only covers the first paragraph of the v1 §6 narrative.

### G2 — Known limitations (carried into future work)

1. **Long-form encoder crash.** The full v1 §6 narrative (synthesized via `say` to ~100 s of audio) crashes the app with SIGKILL/jetsam ~3 s into transcription, before any tokens come back. The CTC Conformer encoder's block-wise attention is configured for `context_size=200` so memory should stay bounded, but something during the encoder forward pass on the 1.6 M-sample input pushes the app over the 6 GB cap. Future work: chunked encode (process audio in 30-s windows, free intermediate tensors between), KV cache pruning, or upstream investigation. Sprint 1 G2 ships with a 14-s fixture as the working baseline; long-form audio is parked for a Sprint 2/3 polish.
2. **Keyword biasing under-tuned.** "MEDEVAC" → "metavac"; "8734" → kept; "9120" → "9012-0"; "44.50" → "444.50". The keyword list in `GraniteSpeechPrompt.asr` is concatenated as plain text — Granite Speech doesn't expose a separate biasing parameter. Future work: experiment with prompt phrasing, evaluate whether the upstream model card's "keyword list biasing" doc applies to mlx-community quantizations.
3. **Empty-result display bug fixed in commit.** `.result` STT events sometimes carry `output.text == ""` and rely on the caller's accumulator. Earlier code overwrote `transcriptText` to empty on result; fixed to only overwrite when `final.isEmpty == false`.
4. **Live mic capture via `TranscriptStream.start(audioURL:)` still throws.** G2 ships only the file-based transcribe path through the bake-off. Live mic chunked decode is a future phase.

### G3 — Live mic record-then-transcribe (2026-05-10)

- `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` placeholder body
  replaced with a real live-mic implementation. Cribs the
  `AVAudioEngine` + `AVAudioFile` AAC writer pattern from
  `SpeechRecognizer.swift` (configureSession, installTap on input
  node, applyGain / copyBuffer / computeRMS helpers, ProtectedWrite
  pre-create + markProtected). On `stop()` the actor closes the
  file and runs `runtime.transcribe(audioURL:)` over the captured
  M4A; emits a single final `RecognitionUpdate` with the full
  transcript before finishing the stream. Real-time chunked decode
  is **not** implemented — see "Known limitations" §1 below.
- `TCCC_IOS/DevTools/GraniteLiveView.swift` — DevTools view: red
  RECORD button (toggles to STOP), three memory gauges
  (Resident / **Footprint** in bold / Available) with color thresholds
  off `MemoryMonitorObserver.warning/criticalThresholdBytes`, memory
  pressure event banner, resolver-source line. Status pill
  reflects priming → recording → transcribing → complete | failed.
- `DevToolsLandingView` adds a fourth "Live" tile alongside Sender /
  Receiver / Bake-off. `DevToolsRootView` adds `.graniteLive` route.
- `GraniteSpeechTranscriptStream.primedSource` exposed so the live
  view can render the resolver-source row.

### G3 — Hardware validation (iPhone 17 Pro, iOS 26.2)

- DevTools → Live view loads cleanly, mic permission prompt fires on
  first RECORD tap.
- Resident + Footprint + Available gauges tick at 1 Hz; pressure
  banner does not fire under normal load.
- Recording produces an M4A file in the app's temp directory
  (or the operator-supplied audioURL if any), then the runtime
  transcribes it on STOP and the transcript appears in the panel.
- **Crash mode**: a long-running RECORD session (multi-tens of
  seconds) ramps `phys_footprint` from the 2.2 GB post-load
  baseline up toward the 6 GB cap. Memory pressure crosses
  warning then critical, and eventually iOS jetsam-kills the app.
  Root cause documented in "Known limitations" §2.

### G3 — Known limitations (carried into Sprint 2)

1. **Single-shot transcribe still hits the encoder cap.** The
   record-then-transcribe path runs the full captured audio through
   `model.generateStream(audio: fullArray)` in one pass — same
   single-shot pattern that crashes on the 5-min fixture per G2.
   Recordings beyond ~30 s will fail at transcribe time.
   Sprint 2/3 work is to wire chunked-encode using the patterns
   documented in `RECON_NOTES.md`'s sibling
   `PRIOR_AUDIO_PATTERNS.md` — specifically the 60 s-with-3 s-overlap
   shape from Mike's Python prototype at
   `TCCC_FEB_2026/src/audio.py:115-173`.
2. **Live-recording mailbox leak.** Tap-callback fires ~46 Hz at
   16 kHz / 1024-frame buffers; each callback enqueues a
   `Task { await self?.ingestBuffer(copy) }` carrying a buffer
   copy. The actor's effective drain rate is bounded by AVAudioFile
   write latency + AAC encode, which is slower than the producer
   under sustained recording. Mailbox grows unboundedly, holding
   buffer copies in memory. Observed: footprint reached 4.46 GB
   (post-load baseline 2.16 GB → +2.3 GB live-mic accumulation)
   inside ~30 s of mic capture. The fix is a back-pressured writer
   queue (bounded mailbox, drop-oldest on overflow) — captured in
   `PRIOR_AUDIO_PATTERNS.md`'s anti-pattern list and slated for
   Sprint 2's chunked-encode work where the same pipeline is
   rebuilt with explicit back-pressure.
3. **MemoryMonitorLog.csv not yet wired during recording.** v3 §13
   acceptance criterion 7 expects `MemoryMonitorLog.csv` to be
   non-empty after a Granite Live session; the `MemoryMonitorCSVLogger`
   class exists in TCCCAudio but isn't called from the live view
   yet. Future polish; doesn't block Sprint 1's primary deliverable.
4. **Long-form fixture still doesn't validate.** v3 §13 criterion 5
   expects "5-min fixture transcribes with keyword recall ≥ 90%"
   — that's the §6 narrative the bake-off was built for. The 14 s
   fixture works, the 100 s fixture crashes (G2 §"Known
   limitations"), so this acceptance criterion lands as **partial**
   in Sprint 1's acceptance gate.

## Sprint 2 design research blockers (2026-05-10, post-Sprint-1)

Recorded after Sprint 1 closure (tag `sprint-1-granite-speech-foundation`,
commit `e13ecc4`). **The Sprint 2 spec cannot be written until this
research lands** — the choice between the three approaches below has
load-bearing architectural consequences (chunk-boundary stitching, KV
cache lifetime, mailbox backpressure shape, transcript continuity UX,
all flow from this decision).

The three approaches to compare for chunked-encode in Granite Speech 4.0
1B 5-bit:

1. **Single-shot encode (current Sprint 1 baseline) vs non-encoded
   chunking.** The current pipeline runs the full audio array through
   `model.generateStream(audio: fullArray)` in one pass — works for ≤14
   s, crashes the encoder forward pass past ~30 s. A "non-encoded
   chunking" variant feeds audio into the model in some chunked shape
   *without* invoking the full encoder per chunk (e.g., streaming raw
   PCM windows into a shared encoder state, or sliding-window encode
   without re-encoding overlapped frames). Need quantified comparison:
   total wall-clock, peak `phys_footprint`, tokens-per-second on iPhone
   17 Pro, transcript quality vs single-shot baseline.

2. **Non-encoded chunking, very short windows (~3-4 s).** Hypothesis:
   tiny PCM windows fed directly into the model's audio path keep the
   per-chunk encoder pass small enough that peak memory stays well
   under the 6 GB cap, at the cost of more chunk-boundary stitching and
   higher per-token amortized overhead. Open question: does
   `MLXAudioSTT.GraniteSpeechModel` support state continuity across
   sub-encoder-block-size inputs at all, or does the encoder's
   `context_size=200` (≈ 10 s of audio at 16 kHz / 160-hop / 5×
   downsample) make 3-4 s windows degenerate into independent
   transcripts that need post-hoc stitching?

3. **Encoded chunking, longer windows (~10 s).** Hypothesis: 10 s
   chunks align with the encoder's native `context_size=200`, so each
   chunk is a clean encoder pass with a complete attention window. Boundary
   stitching uses 1-3 s overlap (matches `TCCC_FEB_2026/src/audio.py:115-173`'s
   60s/3s pattern but at smaller scale). Open question: does running
   the encoder at its native block size give sane memory bounds (the
   single-shot 100 s case crashes at ~3 s into transcribe = first
   encoder pass on 1.6 M samples; a 10 s chunk is 1/10 the input —
   peak should fit), and do the decoded chunks compose into a coherent
   transcript when the LM decoder sees them as separate
   `generateStream` invocations vs one continuous one?

**What to measure on each approach:**
- Wall-clock total transcribe time for a fixed-length input (use the
  existing 14 s and 100 s fixtures for parity).
- Peak `phys_footprint` (MemoryMonitor + CSV logger captured per-tick).
- Tokens-per-second (via STTGenerationInfo).
- Keyword recall on the v1 §6 token list (use the full 5-min narrative
  re-synthesized — Sprint 1 punted at the first paragraph).
- Transcript continuity at chunk boundaries (manual eyeball + diff
  against single-shot baseline on short fixtures where single-shot
  works).

**Resumption pointer**: when Sprint 2 starts, the design pass reads
back from `SPRINT_1_ACCEPTANCE.md` §"Sprint 2 carry-over" +
`PRIOR_AUDIO_PATTERNS.md` Top Pattern #1 + this blocker section.
Spawn a research subagent (same shape as the one that produced
`PRIOR_AUDIO_PATTERNS.md`) to fetch the IBM Granite Speech model card +
any chunked-decode notes from the upstream `mlx-audio-swift` repo
since v0.1.2 was tagged. The chunk-vs-overlap research is then a
gated-by-spec activity, not a pure code activity.

## Sprint 2 design research (2026-05-10)

Research document: `docs/research/2026-05-10-audio-ingestion-comparison.md`.

Status: **source-backed but not physically complete**. Do not tag
`sprint-2-research-complete` until the A/B/C chunking sweep runs on the
physical iPhone and fills the doc's `BLOCKED:` measurement gaps.

Important correction: pinned `mlx-audio-swift` source shows Granite
Speech `context_size=200` is about **4 seconds** of raw 16 kHz audio,
not about 10 seconds. The path is 160-sample STFT hop (100 mel frames/s)
then pair-stacking into about 50 encoder frames/s. Ten-second chunks may
still win after measurement, but they are an engineering latency/quality
choice, not the native encoder context boundary.

Architecture conclusion for Sprint 2 planning: treat Granite
`generateStream(audio:)` as independent chunked batch ASR. The pinned
implementation creates fresh audio features and a fresh decoder KV cache
per call; it does not expose encoder-state continuation across chunks.
Back-pressure on the capture side remains mandatory regardless of window
size.

---

### G4 — Sprint 1 acceptance gate (2026-05-10)

- `SPRINT_1_ACCEPTANCE.md` written at repo root. Walks v3 §13's nine
  criteria with pass / partial / fail markings + evidence per
  criterion.
- Outcome: **partial Sprint 1 acceptance**. Granite Speech runs
  end-to-end on physical iPhone 17 Pro within the 6 GB entitlement
  cap for short audio (≤ 14 s file fixture, ≤ ~30 s live mic).
  Long-form audio + back-pressured live-mic capture are Sprint 2's
  primary work, guided by the patterns in `PRIOR_AUDIO_PATTERNS.md`.
- Commit tagged `sprint-1-granite-speech-foundation` on push.
- Sprint 2 carry-over enumerated in `SPRINT_1_ACCEPTANCE.md`
  §"Carry-over to Sprint 2" — chunked-encode, back-pressured writer,
  CSV logger wiring, §6 5-min fixture re-run, hot-seat integration,
  real iCloud-Drive (not in-sandbox) reinstall test.
