# TCCC.ai iOS — Audio Transcription + Structured Extraction Sprint Spec (v2, historical)

> **⚠ HISTORICAL — superseded by `SPRINT_TCCC_AUDIO_LLM_V3.md`.**
>
> Preserved as the planning record where the architecture got real (two-pass, memory monitoring, runtime-computed RAM cap, mlx-audio-swift v0.1.2 verified, `mlx-swift-structured` for grammar-masked decoding). **Do not implement from this document.** v2 still assumed a greenfield repo and contained several decisions that were either rejected by Mike or invalidated by the agent's repo recon:
>
> 1. **`TCCCAudioLLM/` greenfield subsystem** with `TCCCTranscriptionEngine`, `TemplateStore`, `SlotFillerRules`, `TCCCRecordingView`, `TCCCTemplateView`, `TCCCAudioManager`. All duplicates of existing repo seams (`GraniteSpeechTranscriptStream` placeholder, `TranscriptSegmentLedger`, hot-seat packet builder, `GraniteSchemaValidator`, `GraniteReviewQueue`, `LiveCaptureScreen`, audio capture + gain in existing ASR backends). v3 §4 has the explicit "what NOT to build" mapping.
> 2. **Lane B parallel work tree** for Canary-Qwen on a separate branch with a separate Claude Code instance. Rejected by Mike. Single trunk on `main`. Canary becomes a future C-phase sprint when Granite is shipped, as a separate document — not a parallel branch.
> 3. **`Embed & Sign` IPA bundle storage** with `huggingface-cli download` into `TCCC_IOS/Resources/Models/`. Replaced by the multi-source resolver (Files.app open-in-place primary via `UIDocumentPickerViewController` + persistent security-scoped bookmark; bundle resource and `MLXBackend.prefetch()` HF-cache as fallbacks). Files.app open-in-place storage survives app reinstalls — IPA bundling does not.
> 4. **Model storage location.** v2 §G3 used `TCCC_IOS/Resources/...` (app target). The agent's recon revealed this would violate AGENTS.md's "no logic in app target" rule and that the new MLX-heavy code belongs in a new `Packages/TCCCAudio` local package, with `Packages/TCCCKit` reserved for pure-logic modules.
> 5. **Single-sprint scope (G0–G6).** v3 splits this into Sprint 1 (Granite Speech transcribes on device with sane memory) and Sprint 2 (transcript flows into the existing hot-seat without regressing Apple Speech / Parakeet defaults). Two separate validation gates.
>
> What v2 got right and v3 carries forward intact: the two-pass architecture, the four-quantization ladder, mlx-audio-swift v0.1.2 as the runtime, mlx-swift-structured for grammar-masked decoding, `phys_footprint`-based memory monitoring with runtime-computed thresholds, sentence-level timestamps from VAD chunk boundaries plus punctuation, the memory entitlement strategy with the App-Store-stripping caveat.

---

**Sprint owner:** Mike (LCDR, NMCB-4 Battalion Surgeon)
**Target device:** iPhone 17 Pro (12 GB RAM, A19 Pro)
**Repo:** existing TCCC iOS repo (sign-in + scaffolding already wired)
**Working branch (Lane A):** `main`
**Working branch (Lane B):** `lane-b-canary-qwen` (separate Claude Code instance — see §11)
**Token budget:** ≤200K per phase; if a phase blows the budget, split it and document the split in `CLAUDE.md`.

**v2 changelog** (vs. the v1 spec at `SPRINT_TCCC_AUDIO_LLM.md`):
- Two-pass architecture: ASR → transcript → text-LLM with constrained JSON. Rejects single-pass audio→JSON entirely.
- Model stack changed: Granite Speech 4.0 1B (mxfp4/4bit/5bit ladder) + Granite 4.0 H 1B **instruct** for JSON.
- Renamed `TCCCSynthesisEngine` → `TCCCTranscriptionEngine` (synthesis = TTS).
- Added `mlx-swift-structured` for grammar-masked decoding.
- Added `mlx-audio-swift` v0.1.2+ as the verified Swift runtime for Granite Speech 4 (PR #95).
- Memory ceiling raised from 3.5 GB to a runtime-measured cap based on `os_proc_available_memory()` minus a safety buffer; `phys_footprint` (not `resident_size`) is the gauge metric.
- New §7 Memory pressure monitoring with three gauges, OSSignposts, and entitlement strategy.
- New Lane B (§11): Canary-Qwen NeMo→MLX adapter port as a separate Claude Code instance on a separate branch. Hedge, not fallback.
- New §16: Download & documentation reference card.

---

## 1. Objective

Land an iOS prototype that:

- Captures live audio via `AVAudioEngine` with real-time gain metering and dynamic makeup gain.
- Runs **Granite Speech 4.0 1B** (MLX-quantized, bundled, mmap-loaded, no remote download) on-device for keyword-biased ASR via `mlx-audio-swift`.
- Feeds rolling timestamped transcript chunks to **Granite 4.0 H 1B Instruct** (4-bit MLX) via `mlx-swift`, with grammar-masked JSON decoding via `mlx-swift-structured`, to produce 9-Line MEDEVAC, ZMIST, and DD Form 1380 output.
- Renders a SwiftUI view with: waveform reacting to mic input, gain gauge, three memory gauges (resident / footprint / available), live template population, and source-attributed transcript spans.
- End-to-end verifies against a bundled 5-minute test narrative (§6).

Not in scope: single-pass audio→JSON, the speech model emitting structured output directly, or any architecture that depends on the speech LLM doing reasoning beyond its trained ASR/AST role.

---

## 2. Locked Decisions (Do Not Re-Litigate)

| Decision | Value | Rationale |
|---|---|---|
| Architecture | **Two-pass:** ASR → transcript → text-LLM with constrained JSON | Granite Speech is trained for ASR/AST. Single-pass audio→JSON would rely on a behavior not in its training distribution; safety filters fall back to plain transcription. Auditable transcripts are also a medical-legal feature. |
| Speech model (primary) | `mlx-community/granite-4.0-1b-speech-5bit` (2.22 GB) — README-documented Swift integration target | Confirmed Swift loader path; Apache 2.0; WER 5.52 on Open ASR Leaderboard |
| Speech model ladder (in priority order) | 1. `granite-4.0-1b-speech-mxfp4` (1.93 GB) 2. `granite-4.0-1b-speech-4bit` (1.99 GB) 3. `granite-4.0-1b-speech-5bit` (2.22 GB, README target) 4. `granite-4.0-1b-speech-8bit` (2.9 GB, accuracy benchmark only) | Smallest viable wins on device; 5-bit is the documented baseline; 8-bit is a Mac-side accuracy reference, not a default device target |
| Text LLM (JSON pass) | `mlx-community/granite-4.0-h-1b-4bit` (~823 MB, **instruct-tuned**) | Instruction-tuned gives better field extraction and follow-the-schema behavior than the base variant |
| Text LLM control | `mlx-community/granite-4.0-h-1b-base-4bit` (~823 MB) | Run head-to-head on the same fixture transcript to confirm instruct-tuned wins for this task |
| Constrained decoding | `petrukha-ivan/mlx-swift-structured` v0.1.0+ (Apache 2.0) | XGrammar-based grammar-masked logits; JSON Schema, `@Generable` (iOS 26+), regex, EBNF; 3–10% generation overhead |
| Speech runtime | `Blaizzy/mlx-audio-swift` v0.1.2+ (MIT) — `MLXAudioSTT.GraniteSpeechModel` | PR #95 added Granite Speech 4 (Mar 14, 2026). Top-level README's STT model table is stale — verify Granite presence by inspecting `Sources/MLXAudioSTT/Models/GraniteSpeech/`, not the README |
| Text LLM runtime | `ml-explore/mlx-swift` (MIT) | Standard mlx-swift for the Granite text LLM; pinned to whatever tag mlx-swift-structured resolves cleanly against |
| Audio framework | `AVFoundation` (`AVAudioEngine`) | iOS standard; tap mic, install tap on mixer node |
| Sample rate | 16 kHz mono Float32 | Granite Speech encoder contract |
| Model storage | Xcode bundle resource (`Embed & Sign`); load via `GraniteSpeechModel.fromPretrained(modelPath:)` overload, NOT the HF-string overload | "No remote download" is a hard requirement |
| Branching | Lane A on `main`; Lane B on `lane-b-canary-qwen` | Mike's standing rule has explicit override for the Lane B hedge |
| Backgrounding | `UIBackgroundTask` wrap on the audio engine | Survive screen lock during recording |
| Memory entitlements | Both `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing` | See §7 — entitlement is stripped on App Store distribution but works for Apple Developer Enterprise / MDM-deployed builds |
| KV cache | 8-bit quantization, prune-on-pressure (see §7) | Long-narrative survival |

---

## 3. Repo Recon (Phase 0 Output)

Before touching code, inventory the existing repo and emit a `PHASE_0_RECON.md` covering:

- Bundle identifier, deployment target, Swift version, Xcode version.
- Existing sign-in flow (file paths, key types, any auth tokens) — **do not break this**.
- Existing `Info.plist` keys; specifically `NSMicrophoneUsageDescription` (add if missing).
- Existing entitlements file; add `com.apple.developer.kernel.increased-memory-limit` (Boolean YES) and `com.apple.developer.kernel.extended-virtual-addressing` (Boolean YES).
- Existing `AppDelegate` / `SceneDelegate` / SwiftUI `App` entry point.
- Existing module structure — new code goes in a top-level folder `TCCCAudioLLM/`.
- Existing dependency manager (SwiftPM expected). List current packages.
- Existing test target name and any existing CI hooks.

If anything is unclear, halt and emit a `BLOCKED:` note rather than guessing.

---

## 4. Data Structures (Locked)

Templates and the slot-filler are unchanged from v1 — Codable structs in `TCCCAudioLLM/Templates/`, `Optional` for every field, `nil` means "not yet observed." See `SPRINT_TCCC_AUDIO_LLM.md` §4 for the full enum list, `Mechanism`, `Injury`, `AVPU`, `PulseStrength`, `Stability`, `EvacPriority`, `Analgesic`, `Antibiotic`, `HemorrhageRx`, `FluidProduct`, `Route`, `MedAdmin`, `NineLine`, `PrecedenceCounts`, `ZMIST`, `Tourniquet`, `DD1380`, `VitalsRow`.

The five hard-coded slot-filler rules also remain (unstable override, TQ requirement, field locking ≥0.85 confidence, source attribution, silence handling).

**One v2 addition:** every committed field carries not just a transcript snippet but a `(start_time: TimeInterval, end_time: TimeInterval)` pair from the audio ring buffer (see §8).

---

## 5. Phases

Ordered. Each phase ends with autonomous verification. Each phase commits with the message format in §13.

### Phase 0 — Repo recon, dependency wiring, entitlements
**Goal:** Inventory repo, add dependencies, prepare scaffolding, request memory entitlements.

**Tasks:**
1. Run `find . -name "*.swift" | head -40`, inspect `.xcodeproj`, `cat Info.plist`, `cat *.entitlements`. Emit `PHASE_0_RECON.md`.
2. Add SwiftPM dependencies (pin tags after `swift package resolve` succeeds — do not invent versions):
   ```swift
   .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.2"),
   .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
   .package(url: "https://github.com/petrukha-ivan/mlx-swift-structured.git", from: "0.1.0"),
   ```
   Products to depend on:
   ```swift
   .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
   .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
   .product(name: "MLXLM", package: "mlx-swift"),
   .product(name: "MLXStructured", package: "mlx-swift-structured"),
   ```
3. Add `NSMicrophoneUsageDescription` to `Info.plist`: `"TCCC.ai uses the microphone to capture casualty-care narration for on-device structured documentation."`
4. Add the two memory entitlements (`com.apple.developer.kernel.increased-memory-limit`, `com.apple.developer.kernel.extended-virtual-addressing`). Document in `TCCCAudioLLM/CLAUDE.md` that App Store distribution will strip these (see §7).
5. Create directory `TCCCAudioLLM/` with subfolders: `Audio/`, `Templates/`, `Inference/`, `UI/`, `Resources/models/`, `Resources/test_audio/`, `Memory/`, `Tests/`.
6. Create `TCCCAudioLLM/CLAUDE.md` for sub-context.

**Verification:**
- `xcodebuild -scheme <existing-scheme> -destination 'generic/platform=iOS' build` succeeds.
- `swift package resolve` succeeds; Package.resolved committed.
- New folders exist; existing sign-in flow files untouched (`git diff --stat` shows only additions).

**Commit:** `phase 0: tccc audio-llm scaffolding + mlx audio/structured deps + memory entitlements`

---

### Phase 1 — Templates + state machine (no audio, no model)
Identical to v1 Phase 1 — Codable templates, `TemplateStore: ObservableObject`, `SlotFillerRules`, `MockExtraction` for testing, full `TemplateStoreTests` coverage.

**v2 addition:** `MockExtraction` outputs include synthetic `(start_time, end_time)` pairs so timestamp plumbing is exercised before audio enters the picture.

**Commit:** `phase 1: tccc templates + slot-filler state machine + timestamp plumbing`

---

### Phase 2 — Audio engine with memory monitoring
**Goal:** Working `AVAudioEngine` capture with metering, 16 kHz mono resampling, ring buffer with timestamps, and the three-gauge memory monitor.

**Tasks:**
1. Implement `TCCCAudioManager: ObservableObject` in `TCCCAudioLLM/Audio/`. Use `AVFoundation`.
2. `@Published` properties: `inputLevelDb`, `appliedGain`, `isRecording`.
3. Install a tap on a mixer node. Compute RMS → dBFS per buffer. Apply makeup gain (boost 2× when dB < -30; clamp).
4. Resample to 16 kHz mono Float32 via `AVAudioConverter`. Push into `TCCCAudioRingBuffer` sized for 4-second chunks (Granite Speech encoder block size). **Each ring-buffer entry carries `(audio: [Float], startHostTime: UInt64, endHostTime: UInt64)`** so transcript segments can later be tagged with sentence-level timestamps (see §8).
5. Wrap session lifecycle in `UIBackgroundTaskIdentifier`.
6. Configure `AVAudioSession` category `.record`, mode `.measurement`, options `.mixWithOthers`.
7. Implement `MemoryMonitor` in `TCCCAudioLLM/Memory/` with three published metrics — `residentMB`, `physFootprintMB`, `availableMB` — plus a `pressure` enum (`.normal | .warning | .critical`). See §7 for the implementation contract. Subscribe to `DispatchSource.makeMemoryPressureSource`. Emit OSSignposts on every state change.

**Verification:**
- `xcodebuild test`: a unit test feeds a known sine wave through the resampler, asserts output is 16 kHz mono and RMS matches expected ±5%; a separate test asserts the ring buffer's timestamps are monotonic and gap-free.
- `xcodebuild build` succeeds with no warnings on `import AVFoundation`.
- `MemoryMonitorTests` asserts that all three metrics report non-zero values and that `physFootprintMB <= residentMB + compressedSlack` (sanity check).

**Commit:** `phase 2: avaudioengine + ring buffer with timestamps + memory monitor`

---

### Phase 3 — Granite ASR characterization (no JSON yet)
**Goal:** Bundled Granite Speech weights load via `mmap`, run keyword-biased ASR on the 5-minute fixture, characterize transcript quality, keyword recall, load time, and peak `phys_footprint` across the four-quantization ladder.

**Tasks:**
1. **Procure all four MLX speech artifacts.** On a Mac (off-device, since these are bundle resources):
   ```bash
   mkdir -p TCCCAudioLLM/Resources/models
   for v in mxfp4 4bit 5bit 8bit; do
     huggingface-cli download \
       --local-dir TCCCAudioLLM/Resources/models/granite-4.0-1b-speech-$v \
       mlx-community/granite-4.0-1b-speech-$v
   done
   ```
   At ship time, only ONE of these will be in the actual app bundle (chosen empirically); the others are committed under git-lfs for benchmark comparisons. Apache 2.0 attribution goes in `TCCCAudioLLM/Resources/models/LICENSE-NOTICES.md`.
2. **Validate the Swift loader API by inspecting the source folder, not the top-level README.** Run:
   ```bash
   git clone https://github.com/Blaizzy/mlx-audio-swift
   cd mlx-audio-swift && git checkout v0.1.2
   find Sources/MLXAudioSTT/Models/GraniteSpeech -maxdepth 2 -type f -print
   grep -R "GraniteSpeechModel\|fromPretrained\|modelPath\|Bundle" -n Sources
   cat Sources/MLXAudioSTT/Models/GraniteSpeech/README.md 2>/dev/null
   ```
   Document the exact loader signature in `TCCCAudioLLM/CLAUDE.md`. The expected pattern (extrapolated from sibling models like `LFM2AudioModel`):
   ```swift
   // HF-string overload (NOT used in production — bundled weights)
   let model = try await GraniteSpeechModel.fromPretrained(
     "mlx-community/granite-4.0-1b-speech-5bit"
   )
   // Local-path overload (production path)
   let bundleURL = Bundle.main.url(
     forResource: "granite-4.0-1b-speech-5bit",
     withExtension: nil
   )!
   let model = try await GraniteSpeechModel.fromPretrained(modelPath: bundleURL.path)
   ```
   If the local-path overload doesn't exist on v0.1.2, halt and emit `BLOCKED:` — do not silently fall back to network resolution at runtime.
3. Implement `TCCCTranscriptionEngine` in `TCCCAudioLLM/Inference/`:
   - `init()` loads the model from the bundled local path (fail-fast if missing).
   - `transcribe(_ pcm: [Float], startTime: TimeInterval, keywords: [String]) async throws -> TranscriptSegment` returns `(text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float?)`.
   - The keyword-biasing prompt is the documented Granite Speech format: append `Keywords: <kw1>, <kw2>, ...` to the transcription prompt. Initial keyword set:
     ```swift
     let TCCC_KEYWORDS = [
       "tourniquet", "TXA", "GSW", "AVPU", "SpO2", "MEDEVAC", "DD1380",
       "ZMIST", "9-line", "MARCH", "hemorrhage", "pneumothorax", "ketamine",
       "fentanyl", "morphine", "moxifloxacin", "ertapenem", "cefazolin",
       "Hextend", "lactated ringer's", "whole blood", "plasma",
       "needle decompression", "chest seal", "NPA", "cric",
       "Reaper", "Dawson", "NKDA"
     ]
     ```
4. Bundle the 5-minute test narrative as `test_5min.wav` (16 kHz mono) under `TCCCAudioLLM/Resources/test_audio/`. Generate via `say -o tmp.aiff "..." && afconvert tmp.aiff test_5min.wav -d LEI16@16000 -f WAVE -c 1` from the narrative text in §6.
5. Wire `MemoryMonitor` to log `phys_footprint` deltas around the load and around each chunk inference, via OSSignpost intervals.

**Verification — `Phase3CharacterizationTests`:**
For each of the four quantizations (mxfp4, 4bit, 5bit, 8bit), in priority order, on the actual iPhone 17 Pro device (or simulator with caveats noted):
1. Load the model. Record load time and `phys_footprint` delta.
2. Transcribe the 5-minute fixture. Record total transcription time and peak `phys_footprint`.
3. Compute keyword recall against this list (must hear at least these tokens):
   ```
   8734, 9120, 44.50, Reaper, urgent surgical, GSW, chest, AVPU P, pain,
   SpO2, 88, 93, TXA, Hextend, chest seal, needle decompression, NKDA,
   Dawson, RD6942, 6942
   ```
4. Emit `PHASE_3_RESULTS.md` table: variant × load_time × peak_phys_footprint × transcription_time × keyword_recall_pct × WER_against_reference.

**Promotion rule:** the smallest variant that passes keyword-recall ≥ 90% AND keeps peak `phys_footprint` under §7's runtime cap is promoted to the production bundle. If only 8-bit clears recall, keep 8-bit; if mxfp4 clears, promote mxfp4. Document the choice and the alternatives in `TCCCAudioLLM/CLAUDE.md`.

**Do not assess JSON quality in this phase.** That is Phase 3.5's job.

**Commit:** `phase 3: granite asr characterization across quantization ladder`

---

### Phase 3.5 — Text-only JSON extraction (no live audio)
**Goal:** Bundled Granite 4.0 H 1B Instruct (4-bit MLX) reads the known-good fixture transcript and produces 9-Line / ZMIST / DD1380 JSON via `mlx-swift-structured` grammar-masked decoding. Isolate the structured-output problem before live audio noise enters.

**Tasks:**
1. Procure both text artifacts:
   ```bash
   huggingface-cli download \
     --local-dir TCCCAudioLLM/Resources/models/granite-4.0-h-1b-4bit \
     mlx-community/granite-4.0-h-1b-4bit
   huggingface-cli download \
     --local-dir TCCCAudioLLM/Resources/models/granite-4.0-h-1b-base-4bit \
     mlx-community/granite-4.0-h-1b-base-4bit
   ```
   Both bundled under git-lfs. Apache 2.0 attribution updated in `LICENSE-NOTICES.md`.
2. Implement `TCCCExtractionEngine` in `TCCCAudioLLM/Inference/`:
   - Loads either the instruct or base text LLM via `mlx-swift`'s `LLMModelFactory.shared.loadContainer(directory:)`.
   - Builds a `Grammar` from the Codable struct schemas. Two paths to evaluate:
     - **Path A (preferred, iOS 26+):** Annotate `NineLine`, `ZMIST`, `DD1380` with `@Generable` and `@Guide(description:)`. Use `Grammar.generable(NineLine.self)`.
     - **Path B (iOS 17 fallback):** Hand-author `JSONSchema.object(...)` from the Codable definitions. Use `Grammar.schema(schema)`.
   - Generation method: `generate(input:context:grammar:generating: NineLine.self)` returning a typed value, or the streaming `partially:` variant if you want progressive UI updates during the JSON pass.
3. Compose the prompt template:
   ```
   You are a tactical combat casualty care documentation assistant.
   Extract structured medical documentation from this transcript.
   Output a single JSON object matching the schema for {nineLine|zmist|dd1380}.
   Fields not heard in the transcript MUST be null. Never guess.

   Currently locked fields (do not contradict): {locked_state}
   Transcript:
   {full_transcript_or_chunk}
   ```
4. Run head-to-head: instruct LLM vs. base LLM on the same fixture transcript. Score on (a) field coverage, (b) field correctness, (c) hallucination rate (committed fields with no transcript evidence), (d) generation time, (e) memory delta.

**Verification — `Phase35JSONTests`:**
- Load each text LLM. Assert load time < 3s on iPhone 17 Pro and `phys_footprint` delta < 1.0 GB.
- For each of the three templates, generate JSON from the known-good fixture transcript. Assert: parses as valid JSON, matches the Codable schema, contains the expected fields per §6 acceptance baseline, no hallucinated fields beyond `uncertainSpans`.
- Emit `PHASE_3_5_RESULTS.md` — instruct vs. base scoreboard.

**Promotion rule:** instruct LLM ships unless base demonstrably outperforms it on field correctness.

**Commit:** `phase 3.5: granite text llm + mlx structured json extraction`

---

### Phase 4 — Live audio → transcript → JSON
**Goal:** Wire Phase 2's audio ring buffer to Phase 3's ASR to Phase 3.5's text-LLM JSON pass. Asynchronous slot filling. Context stitching is text-state, not multimodal KV.

**Tasks:**
1. Add `TCCCPipeline` actor coordinating: ring-buffer chunks → `TCCCTranscriptionEngine.transcribe(...)` → `RollingTranscript` (timestamped segments) → `TCCCExtractionEngine.extract(...)` → `SlotFillerRules.apply(...)` → `TemplateStore.commit(...)`.
2. Run on a dedicated `Task.detached(priority: .userInitiated)`. Backpressure: if the text-LLM pass falls behind, drop oldest pending JSON tasks but never drop transcript chunks (audit trail beats latency).
3. Context stitching: each JSON pass receives `(locked_field_summary, last_N_transcript_chunks, unresolved_mandatory_fields)` as text. KV cache is text-only — no multimodal KV growth across the 5-minute narrative.
4. Implement KV cache pressure response (see §7): on `MemoryMonitor.pressure == .warning`, reduce KV cache to 8-bit or shrink context window; on `.critical`, evict KV cache for the text LLM and recompute on next pass.

**Verification — `Phase4LiveLoopTests`:**
- Inject the 5-min fixture via synthetic real-time playback through `AVAudioPCMBuffer` (no actual mic). After playback completes:
  - Assert all expected fields per §6 are populated with `confidence ≥ 0.85`.
  - Assert `zmist.classification == .unstable` (set by the unstable-override rule, even if model emits `.stable`).
  - Assert each populated field has a non-nil source span and a `(startTime, endTime)` pair within the fixture's 0–300 s range.
  - Insert a deliberate conflicting roster mid-stream and assert it lands in `uncertainSpans`, not the locked field.
  - Assert peak `phys_footprint` stays under the runtime cap throughout.
- Emit `PHASE_4_RESULTS.md`.

**Commit:** `phase 4: live pipeline asr→transcript→json with kv pressure response`

---

### Phase 5 — SwiftUI integration
**Goal:** Single screen showing recording state, gain reactivity, three memory gauges, live template population, and source-attributed transcript spans.

**Tasks:**
1. `TCCCRecordingView`:
   - Top: large red/grey record button bound to `audioManager.isRecording`.
   - Waveform strip: 60-frame rolling buffer of `inputLevelDb`, two overlaid traces — pre-gain (grey) and post-gain (cyan, Tokyo Night Storm). `Canvas` for drawing.
   - Gain gauge: numeric `appliedGain` with a small bar (1.0× to 4.0× range).
   - **Three memory gauges side-by-side** (per §7): Resident MB, Footprint MB (bold; this is the jetsam-relevant number), Available MB. Color-shifts amber at the warning threshold, red at critical.
2. `TCCCTemplateView`: three collapsible sections (9-Line, ZMIST, DD1380). Each field renders with three states:
   - `nil` → grey `"NOT_HEARD"`.
   - Pending (confidence < 0.85) → italic, dimmed.
   - Locked → solid, with a small lock glyph; tap reveals source snippet AND the `[mm:ss–mm:ss]` timestamp range.
3. `TCCCGenerateScriptButton`: emits a plain-text rendering of the current state machine. Copy + share sheet. The exported script preserves `NOT_HEARD` placeholders for unresolved mandatory fields.
4. Wire the existing repo's root navigation so the recording view is reachable post-sign-in. Do not modify any sign-in code.

**Verification:**
- `xcodebuild build` for both Debug and Release succeeds.
- Snapshot tests render `TCCCRecordingView` with three template fixture states (empty, partial, full) against bundled reference PNGs.
- Autonomous simulator run with a `#if DEBUG` "Replay test fixture" button.

**Commit:** `phase 5: swiftui recording + template view + memory gauges + script export`

---

### Phase 6 — End-to-end smoke
**Goal:** One reproducible E2E run against the 5-minute fixture, committed as a baseline.

**Tasks:**
1. UI test target. `E2ETest`:
   - Launches in `#if DEBUG && TCCC_E2E` mode bypassing sign-in.
   - Triggers "Replay test fixture."
   - Waits for script-export to enable.
   - Asserts the exported text contains all expected fields from §6 with their timestamp ranges.
2. Emit `E2E_BASELINE.md`: timing, peak `phys_footprint`, available-memory low-water mark, field coverage %, keyword recall %.

**Verification:**
- `xcodebuild test -scheme <ui-test-scheme> -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` passes.
- `E2E_BASELINE.md` shows ≥ 90% field coverage on the fixture.

**Commit:** `phase 6: e2e smoke + baseline`

---

## 6. Bundled Test Fixture

The 5-minute narrative is unchanged from v1; see that document §6 for the full text. Acceptance baseline (clinically important tokens that MUST be heard for the sprint to ship):

```
8734, 9120, 44.50, Reaper, urgent surgical, GSW, chest,
AVPU P, pain, SpO2, 88, 93, TXA, Hextend, chest seal,
needle decompression, NKDA, Dawson, RD6942, 6942
```

Plus the §6 v1 expected-extraction list for `nineLine`, `zmist`, `dd1380` with their populated fields.

---

## 7. Memory Pressure Monitoring & RAM Ceiling

**Why the v1's 3.5 GB cap was wrong.** That number was a defensive floor for a contested foreground (other apps backgrounded, OS background services consuming budget). Tactical-mode iPhone 17 Pro with everything else force-closed is a different operating regime, and iOS exposes specific knobs for it.

**iPhone 17 Pro envelope:**
- 12 GB unified RAM (LPDDR5X-9600, 76.8 GB/s).
- Standard foreground per-process memory limit: not officially published, but extrapolating from documented iPhone 14 Pro / 15 Pro / 16 Pro patterns onto a 12 GB device, expect **~6–7 GB** before jetsam fires on a stock distribution build.
- With `com.apple.developer.kernel.increased-memory-limit` entitlement on dev / TestFlight / Apple Developer Enterprise / MDM-deployed builds: developers report reaching **~10–15 GB** on 16 GB iPad Pro before jetsam (Apple Developer Forums #770868). Extrapolating to 12 GB iPhone 17 Pro: realistic working ceiling ~9–10 GB.
- **Critical caveat:** the entitlement gets stripped on App Store distribution builds. Same code, same entitlement, hits 15 GB on dev signing, crashes at ~6 GB on App Store. For TCCC.ai's likely distribution posture (Apple Developer Enterprise Program, MDM, or DoD enterprise channel), the entitlement should work. For App Store distribution, plan for the standard limit.

**The right metric is `phys_footprint`, not `resident_size`.** Jetsam terminates apps based on `phys_footprint` from `task_vm_info`, which accounts for compressed memory and IOKit allocations that `resident_size` misses. The v1 `AudioMemoryReporter` reads `resident_size` only — that's the wrong gauge.

**`MemoryMonitor` implementation contract:**

```swift
import Darwin
import os.log

final class MemoryMonitor: ObservableObject {
    @Published var residentMB: Double = 0
    @Published var physFootprintMB: Double = 0
    @Published var availableMB: Double = 0
    @Published var pressure: MemoryPressure = .normal

    enum MemoryPressure { case normal, warning, critical }

    private let signposter = OSSignposter(subsystem: "ai.tccc.memory", category: "memory")

    // resident_size — supplementary
    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }

    // phys_footprint — the jetsam-relevant number
    static func physFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // os_proc_available_memory() — remaining budget before jetsam
    // Available iOS 13+; returns 0 on platforms where it doesn't apply.
    static func availableBytes() -> UInt64 { os_proc_available_memory() }
}
```

**Pressure thresholds (computed at runtime, not hard-coded):**

```swift
let cap = Double(MemoryMonitor.physFootprintBytes() + MemoryMonitor.availableBytes()) / 1_048_576
// e.g. cap ≈ 9000 MB on entitled iPhone 17 Pro foreground

let warningAt = 0.75 * cap   // start KV-cache compaction
let criticalAt = 0.90 * cap  // evict KV cache, halt new inference
```

This means thresholds adjust per device + entitlement state, instead of being baked into the source. A cellular-network user with no entitlement will get a 5 GB cap; an MDM-deployed tactical device with entitlement will get a 9–10 GB cap. Same code, different runtime ceilings.

**Pressure response policy:**
- `.normal` → no action.
- `.warning` → log to OSSignpost; switch KV cache to 8-bit if not already; UI gauge turns amber.
- `.critical` → log + alert (vibration + UI banner); evict text-LLM KV cache; pause new inference for one chunk; resume when pressure subsides; UI gauge turns red.
- Subscribe to `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())` for system-level pressure events that override per-process budget thinking.

**UI surfacing (Phase 5):**
- Three gauges side-by-side: Resident, **Footprint** (bold), Available. Numeric MB + thin colored bar.
- Footprint color shifts at runtime-computed warning/critical thresholds.
- Memory pressure events show as a thin banner across the recording view: `MEM PRESSURE: warning at 18:42:13 — KV compacted` / `MEM PRESSURE: critical at 18:43:02 — inference paused`.

**Logging (always on, even when UI is hidden):**
- OSSignpost `phase_load_model`, `phase_inference_chunk`, `phase_extract_json`, with `phys_footprint` begin/end attributes.
- Console log every memory pressure transition.
- `MemoryMonitorLog.csv` written to app's Documents directory: timestamp, resident_mb, footprint_mb, available_mb, pressure_level, event. This is your jetsam forensics file when something dies.

---

## 8. Sentence-Level Timestamps (Strategy)

Granite Speech 4.0 1B does not emit explicit timestamps in its base ASR mode (the 4.1 Plus variant does, but it's not in this sprint). Sentence-level timestamps are derived from the audio side:

- Each ring-buffer chunk (4-second block) carries `(startHostTime, endHostTime)`.
- Each transcript segment returned from `TCCCTranscriptionEngine.transcribe(...)` inherits the chunk's start/end times verbatim.
- Sentence boundaries within a chunk are inferred from punctuation in the transcript (Granite Speech does emit punctuation/capitalization in base mode); a sentence that spans two chunks gets the union of their time ranges.
- For a future tighter alignment, the optional `mlx-community/Qwen3-ForcedAligner-0.6B-bf16` (already in mlx-audio-swift) can be loaded as a side-pass to back-align transcript words against audio. Not in this sprint.

This delivers the user's stated requirement ("sentence-level is sufficient") without depending on the speech model to emit timing.

---

## 9. Known Issues & Stale Documentation

1. **`mlx-audio-swift`'s top-level README is stale.** The STT model table omits Granite Speech, but PR #95 ("Add granite speech 4") landed in v0.1.2 (Mar 14, 2026) and the `Sources/MLXAudioSTT/Models/GraniteSpeech/` folder + per-model README are the truth. **Always grep source folders, release notes, and PRs before trusting the top-level README of any rapidly-evolving repo.** This was the source of v1's biggest factual error.
2. **The `increased-memory-limit` entitlement is stripped on App Store distribution builds.** See §7. Verify the entitlement is active at runtime by sampling `os_proc_available_memory()` early in app launch and logging it; if it's near the standard limit, the entitlement didn't take effect.
3. **`fromPretrained` API has two overloads** in mlx-audio-swift: HF-string (downloads from network) and `modelPath:` (local directory). Always use the local-path overload in production. Verify both exist on your pinned version.
4. **`@Generable` requires iOS 26+.** For iOS 17–25 deployment targets, use `JSONSchema.object(...)` and `Grammar.schema(...)` instead. The TCCC repo's deployment target governs which path Phase 3.5 uses.
5. **`mlx-swift-structured` is at v0.1.0 (Apr 6, 2026)** — early-stage. Author warns of crashes / unexpected behavior. Pin to the released tag, run their test suite locally before integration, and have a fallback path of plain-generation + `JSONDecoder` validation if the grammar mask misbehaves.

---

## 10. Fallback Paths

| If… | Then… |
|---|---|
| Granite Speech 4.0 1B mxfp4 fails recall threshold | Try 4bit, then 5bit (the README target). 8-bit is benchmark only — don't ship it on device unless §7's runtime cap permits. |
| Granite Speech 4.0 1B fails recall on 5-bit too | Stop and characterize what's failing. Likely audio-pipeline issue (resampling, gain) before model issue. |
| Single-pass JSON extraction (Phase 3.5) produces malformed output even with grammar mask | mlx-swift-structured supports `partially:` streaming with retry — wire automatic single-retry on parse failure before falling through to plain generation + JSONDecoder. |
| iPhone 17 Pro hits jetsam during the 5-min fixture | First check entitlement is active via `os_proc_available_memory()` log. If yes, drop to smaller speech quantization. If still failing, prune KV cache more aggressively (window 256 tokens). |
| `mlx-audio-swift` v0.1.2 lacks the `modelPath:` local-load overload | Halt and emit `BLOCKED:`. Three recovery options: (a) submit a PR to mlx-audio-swift adding the local overload (one-day patch, IBM/Blaizzy is responsive), (b) use the HF-string overload but pre-populate the cache directory at first-launch from bundled weights via a `FileManager.copyItem` call, (c) downgrade to an earlier mlx-audio-swift version if local loading existed earlier. Check option (b) feasibility with `Hub` cache layout. |
| Granite 4.1 2B becomes available with an mlx-community port mid-sprint | Lane B is the fork environment for trying it without disrupting Lane A. Don't swap into Lane A mid-sprint. |
| Lane B (Canary-Qwen) ports cleanly | After Lane A ships, run Lane B head-to-head on the same fixture. If Canary-Qwen wins on field WER for tactical noise, that's the upgrade path for v2.0. Lane B never gates v1.0 ship. |
| `xcodebuild test` flakes in CI but passes locally | `XCTSkip` on CI, do not delete. |

---

## 11. Lane B — Canary-Qwen Parallel Work Tree

**Premise:** Canary-Qwen-2.5B's FastConformer encoder downsamples audio 8× vs. Granite Speech's 10× total, but with a parameter-efficient single-stage that may be more robust to mechanical battlefield noise (rotor wash, engines). It also pairs with Qwen2.5-2.5B-Instruct, which is a first-class citizen in `mlx-swift-examples`. The blocker is the NeMo-side adapter port — there's no MLX-native artifact today.

**This is a hedge, not a fallback.** Lane A ships v1.0 regardless of Lane B's progress. If Lane B succeeds, it informs v2.0. If it fails, no harm done.

**Setup:**
- Fork `aarzamen/TCCC.ai` to a working branch `lane-b-canary-qwen` (or a separate fork repo if the agent prefers tighter isolation).
- Spin up a **separate Claude Code instance** in that branch. Separate `CLAUDE.md` (`LANE_B_CLAUDE.md`), separate `PHASE_*.md` files, separate spec.
- Cross-lane status reporting: each lane updates a shared `LANE_STATUS.md` (in the repo root) once per session with current phase, blockers, and ETA. Both Claude Codes read this on session start.

**Lane B sprint outline (light spec — full spec to be authored by the Lane B agent on Phase 0 completion):**

1. **Phase B0 — Recon.** Inspect `nvidia/canary-qwen-2.5b` checkpoint structure. Map FastConformer encoder weights, LoRA adapter weights, projection layer weights. Document NeMo-specific tensor names vs. mlx-swift's expected naming.
2. **Phase B1 — FastConformer encoder port.** Port to `mlx-swift`. Validate against a known WAV → encoder-output reference computed with NeMo Python on Mac. Numerical equivalence: cosine sim ≥ 0.99 between NeMo and mlx-swift encoder outputs.
3. **Phase B2 — LoRA + projection.** Port LoRA adapters and the linear projection layer. Validate end-to-end encoder→projection→Qwen-input embedding equivalence against NeMo reference.
4. **Phase B3 — LLM wiring.** Use `mlx-swift-examples` LLMModelFactory to load `Qwen/Qwen2.5-2.5B-Instruct` (existing MLX port) and feed projected embeddings into its forward pass. End-to-end: WAV → text transcript matching NeMo output ±5% WER.
5. **Phase B4 — Quantize + bundle.** INT4/INT8 quantization. Bundle for iOS test on iPhone 17 Pro.
6. **Phase B5 — Smoke test on the same 5-min fixture as Lane A.** Same memory budget rules apply (§7). Same keyword-recall acceptance.

**Cross-lane swap criterion (post-Lane-A-ship):** Lane B's transcript on the 5-min fixture beats Lane A's by ≥ 1.0 WER points OR demonstrates better robustness on a synthetic-rotor-wash noise overlay. Otherwise Lane A stays.

**License note:** Canary-Qwen uses CC-BY-4.0; Qwen2.5-Instruct uses Apache 2.0. CC-BY-4.0 is permissive — DoD and Apple App Review have shipped CC-BY-4.0 components. Attribution lives in `LANE_B_LICENSE-NOTICES.md`.

---

## 12. CLAUDE.md Merge Protocol

- **Root `CLAUDE.md`** (existing repo): append-only. Add a section `## TCCC Audio-LLM Subsystem` with one-paragraph summary and link to `TCCCAudioLLM/CLAUDE.md`. Do not modify existing sections.
- **`TCCCAudioLLM/CLAUDE.md`** (new): per-phase journal. Each phase appends a dated section with locked decisions made during execution, API versions pinned, performance numbers measured.
- **`LANE_STATUS.md`** (new, repo root): cross-lane status, updated by both Claude Codes once per session.
- **`LANE_B_CLAUDE.md`** (Lane B branch only): Lane B's per-phase journal.
- Never delete from any `CLAUDE.md`. Supersede with `[SUPERSEDED YYYY-MM-DD: ...]`.

---

## 13. Commit Message Format

```
phase N: <verb> <subject>

- bullet of what landed
- bullet of what was deferred
- bullet of any BLOCKED: items

Token budget: <consumed>/200K
Files changed: <count>
```

Lane A on `main`. Lane B on `lane-b-canary-qwen`. Each lane runs `git push` for its own branch; Lane B never pushes to `main`.

---

## 14. Final Acceptance Criteria (Lane A v1.0)

On a clean iPhone 17 Pro device with the entitlement active:

1. App launches via existing sign-in.
2. Recording view appears, mic permission granted via the prompt added in Phase 0.
3. Pressing record causes the cyan post-gain trace to react to live speech within 100 ms.
4. Memory gauges visible and live-updating; `phys_footprint` stays under §7's runtime cap (75% of `phys_footprint + available_memory` measured at app launch) across the full 5-minute recording.
5. Within 60 seconds of speech-end, the three template panels show populated fields with at least one source span revealed on tap, including `[mm:ss–mm:ss]` timestamp range.
6. Every populated field that came from the model has a non-nil source-span tuple including timestamp range.
7. The "Generate Script" button produces a plain-text export covering all locked fields with `NOT_HEARD` placeholders for unresolved mandatory fields.
8. Keyword recall on the 5-minute fixture ≥ 90% on the §6 token list.
9. `git log --oneline | head -7` shows seven phase commits in §13's format.
10. `MemoryMonitorLog.csv` is non-empty and shows OSSignpost intervals around model load and inference.

If any criterion fails, halt and emit `BLOCKED:`. Do not partial-deliver and label complete.

---

## 15. Out of Scope (Explicitly)

- Single-pass audio→JSON.
- Google Drive upload / off-device sync.
- Encrypted-at-rest storage of generated documents (separate sprint).
- Multi-casualty MASCAL handling.
- Translation / multilingual ops (Granite supports six languages; English-only for sprint 1).
- ATAK plugin packaging.
- Word-level timestamps (sentence-level is sufficient per user requirement; word-level requires Plus variant).
- Granite Speech 4.1 2B (no MLX artifact yet — Lane B-style stretch).
- Lane B delivery (Canary-Qwen NeMo→MLX port runs in parallel but does not gate v1.0).

---

## 16. Download & Documentation Reference Card

| Component | Download / Source | License | Docs |
|---|---|---|---|
| `mlx-audio-swift` v0.1.2 | https://github.com/Blaizzy/mlx-audio-swift | MIT | Top-level README (stale); per-model READMEs in `Sources/MLXAudioSTT/Models/<Name>/README.md` are authoritative |
| `mlx-swift` | https://github.com/ml-explore/mlx-swift | MIT | https://swiftpackageindex.com/ml-explore/mlx-swift |
| `mlx-swift-structured` v0.1.0 | https://github.com/petrukha-ivan/mlx-swift-structured | Apache 2.0 | Repo README; XGrammar tech report arXiv 2411.15100 |
| Granite Speech 4.0 1B mxfp4 | https://huggingface.co/mlx-community/granite-4.0-1b-speech-mxfp4 | Apache 2.0 | Upstream model card https://huggingface.co/ibm-granite/granite-4.0-1b-speech |
| Granite Speech 4.0 1B 4bit | https://huggingface.co/mlx-community/granite-4.0-1b-speech-4bit | Apache 2.0 | Same upstream |
| Granite Speech 4.0 1B 5bit | https://huggingface.co/mlx-community/granite-4.0-1b-speech-5bit | Apache 2.0 | Same upstream |
| Granite Speech 4.0 1B 8bit | https://huggingface.co/mlx-community/granite-4.0-1b-speech-8bit | Apache 2.0 | Same upstream |
| Granite 4.0 H 1B Instruct (4-bit MLX) | https://huggingface.co/mlx-community/granite-4.0-h-1b-4bit | Apache 2.0 | Upstream https://huggingface.co/ibm-granite/granite-4.0-h-1b |
| Granite 4.0 H 1B Base (4-bit MLX) | https://huggingface.co/mlx-community/granite-4.0-h-1b-base-4bit | Apache 2.0 | Upstream https://huggingface.co/ibm-granite/granite-4.0-h-1b-base |
| Apple `os_proc_available_memory` | iOS 13+ system API | Apple SDK | https://developer.apple.com/documentation/foundation/1490575-os_proc_available_memory |
| Apple `task_vm_info` (`phys_footprint`) | mach API | Apple SDK | https://developer.apple.com/forums/thread/770868 (entitlement stripping note) |
| Increased-memory-limit entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit | Apple SDK | Apple Developer Forums #685084, #770868 |
| Extended-virtual-addressing entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing | Apple SDK | Same |

**Lane B references (research-only for Lane A):**

| Component | Download / Source | License | Notes |
|---|---|---|---|
| Canary-Qwen-2.5B (NeMo) | https://huggingface.co/nvidia/canary-qwen-2.5b | CC-BY-4.0 | NeMo-native; no MLX artifact; needs adapter port |
| Qwen2.5-2.5B-Instruct (MLX) | https://huggingface.co/mlx-community/Qwen2.5-2.5B-Instruct-4bit | Apache 2.0 | Already MLX-native; Lane B uses this as the LLM backbone |
| WhisperKit (fallback baseline only) | https://github.com/argmaxinc/argmax-oss-swift | MIT | Reference benchmark; not in Lane A architecture |
| FluidAudio + Parakeet (alt benchmark) | https://github.com/FluidInference/FluidAudio | Apache 2.0 | Reference benchmark; CC-BY-4.0 model card |
| Granite Speech 4.1 2B (stretch) | https://huggingface.co/ibm-granite/granite-speech-4.1-2b | Apache 2.0 | No mlx-community port yet; conversion + Swift loader validation needed before adoption |

---

*End of v2 spec. Lane A: feed this to Claude Code on `main`. Lane B: spawn a separate Claude Code on `lane-b-canary-qwen` branch and have it author its own spec on Phase B0 completion.*
