# TCCC.ai iOS — Audio-LLM Sprint Spec (v1, historical)

> **⚠ HISTORICAL — superseded by `SPRINT_TCCC_AUDIO_LLM_V3.md`.**
>
> Preserved as the initial greenfield planning record. **Do not implement from this document.** v1 was written before repo recon and contains three load-bearing assumptions that turned out wrong:
>
> 1. **Single-pass audio→JSON architecture.** Granite Speech is trained for ASR/AST, not arbitrary structured output. v2 introduced two-pass (ASR → text-LLM with constrained JSON) and v3 confirmed it.
> 2. **Greenfield repo.** The actual repo already has `TranscriptStream`, `GraniteSpeechTranscriptStream` placeholder, hot-seat packet builder, `GraniteSchemaValidator`, `GraniteReviewQueue`, `MLXBackend.generateStructured(...)`, `HFHubCache.contains(modelId:)`, audio capture + gain pattern in existing ASR backends. v3 patches into existing seams instead of creating parallel ones.
> 3. **Model storage via `Embed & Sign` IPA bundle resource.** Hostile to dev iteration since IPA bundling forces re-sideload on every reinstall. The agreed solution is a multi-source resolver with Files.app open-in-place primary (user-managed iCloud Drive or "On My iPhone" via `UIDocumentPickerViewController` + persistent security-scoped bookmark), with bundle resource and `MLXBackend.prefetch()` HF-cache as fallback paths.
>
> See v3 for the canonical, repo-aware, Sprint 1-scoped plan.

---

**Sprint owner:** Mike (LCDR, NMCB-4 Battalion Surgeon)
**Target device:** iPhone 17 Pro (primary), iPhone 15 Pro (fallback)
**Repo:** existing TCCC iOS repo (sign-in + scaffolding already wired)
**Working branch:** `main` (per Mike's rule — no new branches unless explicitly requested)
**Token budget:** ≤200K per phase; if a phase blows the budget, split it and document the split in `CLAUDE.md`.

---

## 1. Objective

Land a working iOS prototype that:

- Captures live audio via `AVAudioEngine` with real-time gain metering and dynamic makeup gain.
- Runs a single-pass Audio-LLM (Granite Speech 4.1 2B, INT4/INT8, MLX-Swift) on-device, bundled — **no remote model download**.
- Asynchronously fills three medical-document templates (9-Line MEDEVAC, ZMIST, DD Form 1380) using a slot-filler state machine with confidence thresholds and field locking.
- Renders a SwiftUI view that shows: waveform reacting to mic input, gain gauge, RAM usage gauge, and live template population.
- End-to-end verifies against a bundled 5-minute test narrative (provided in §6).

This sprint is **not** the place to revisit model choice, architecture, or template format. Those are locked. If any locked decision proves blocking during execution, halt the phase and emit a `BLOCKED:` note in `CLAUDE.md` with the specific obstacle. Do not pivot autonomously.

---

## 2. Locked Decisions (Do Not Re-Litigate)

| Decision | Value | Rationale |
|---|---|---|
| Primary model (ships now) | **IBM Granite Speech 4.0 1B**, INT8 — `mlx-community/granite-4.0-1b-speech-8bit` (already converted, validated, in production use) | Existing MLX artifact, no conversion gamble, WER 5.52 |
| Upgrade target (Phase 3 stretch) | **IBM Granite Speech 4.1 2B**, converted from `ibm-granite/granite-speech-4.1-2b` BF16 safetensors via `mlx_audio.convert` to INT8/INT4 | WER 5.33; +0.2 WER, +keyword biasing improvements; **no published MLX port at sprint start — must self-convert** |
| Fallback if both fail | NVIDIA Canary-Qwen-2.5B INT4 (~1.6GB) | Documented but not built this sprint; NeMo→MLX adapter port is its own side-quest |
| Inference framework | `mlx-audio-swift` (Blaizzy/mlx-audio-swift) for the speech encoder + STT path; `mlx-swift` core for tensor ops | mlx-audio (not mlx-vlm) is the maintained path for Granite Speech; `mlx-audio-swift` is the explicit iOS bridge |
| Audio framework | `AVFoundation` (`AVAudioEngine`) | Standard iOS path; tap mic, install tap on mixer node |
| Sample rate | 16 kHz mono | Granite Speech input contract |
| Constraint generation | JSON-schema-guided (Outlines-style or GBNF where MLX-Swift supports it) | Prevents trailing-comma / hallucinated-key failures on medical-legal output |
| Model storage | Xcode bundle resource (`Embed & Sign`), `mmap`-loaded | "Tired of remote download" — explicit user requirement |
| Branching | Work on `main` | Mike's standing rule |
| Backgrounding | `UIBackgroundTask` wrap on the audio engine | Survive screen lock during recording |
| KV cache | 8-bit quantization, prune on yellow-zone (3.5GB resident) | Long-narrative survival |

---

## 3. Repo Recon (Phase 0 Output)

Before touching code, inventory the existing repo and emit a `PHASE_0_RECON.md` covering:

- Bundle identifier, deployment target, Swift version, Xcode version.
- Existing sign-in flow (file paths, key types, any auth tokens) — **do not break this**.
- Existing `Info.plist` keys; specifically check for `NSMicrophoneUsageDescription` and add it if missing.
- Existing `AppDelegate` / `SceneDelegate` / SwiftUI `App` entry point.
- Existing module structure — where does new code go? Prefer a new top-level folder `TCCCAudioLLM/` to keep the new subsystem isolated.
- Existing dependency manager (SwiftPM expected). List current packages.
- Existing test target name and any existing CI hooks.

If any of the above is unclear, halt and emit a `BLOCKED:` note rather than guessing.

---

## 4. Data Structures (Locked)

These templates are bounded by the TCCC reference materials. Define them as Swift `Codable` structs in `TCCCAudioLLM/Templates/`. Use `Optional` for every field — the slot filler depends on `nil` meaning "not yet observed."

### 4.1 Scoped Enums

```swift
enum Mechanism: String, Codable, CaseIterable {
    case artilleryFragment = "Artillery Fragment"
    case gsw = "GSW"
    case fpvDrone = "FPV Drone"
    case apMine = "AP Mine"
    case clusterMunition = "Cluster Munition"
    case thermobaric = "Thermobaric"
    case missileStrike = "Missile Strike"
    case droneGrenade = "Drone Grenade"
    case atgm = "ATGM"
    case ied = "IED"
    case buildingCollapse = "Building Collapse"
    case rpg = "RPG"
    case mvc = "MVC"
    case primaryBlast = "Primary Blast"
    case secondaryBlast = "Secondary Blast"
    case flashBurn = "Flash Burn"
    case whitePhosphorus = "White Phosphorus"
    case fall = "Fall"
    case bluntForce = "Blunt Force"
    case acoustic = "Acoustic"
}

enum Injury: String, Codable, CaseIterable {
    case massiveHemorrhage = "Massive Hemorrhage"
    case amputation = "Amputation"
    case longBoneFracture = "Long Bone Fracture"
    case tensionPneumothorax = "Tension Pneumothorax"
    case torsoTrauma = "Torso Trauma"
    case tbi = "TBI"
    case maxillofacial = "Maxillofacial"
    case eyeInjury = "Eye Injury"
    case pelvicFracture = "Pelvic Fracture"
    case burnsOver20Pct = "Burns >20%"
    case crushSyndrome = "Crush Syndrome"
    case spinalInjury = "Spinal Injury"
}

enum AVPU: String, Codable { case alert = "A", verbal = "V", pain = "P", unresponsive = "U" }
enum PulseStrength: String, Codable { case strong = "Strong", weak = "Weak", absent = "Absent" }
enum Stability: String, Codable { case stable = "Stable", unstable = "Unstable" }
enum EvacPriority: String, Codable { case urgent = "Urgent", urgentSurgical = "Urgent Surgical", priority = "Priority", routine = "Routine", convenience = "Convenience" }
```

### 4.2 Pharmacy (Bounded Scope)

```swift
enum Analgesic: String, Codable { case ketamine = "Ketamine", fentanyl = "Fentanyl", morphine = "Morphine" }
enum Antibiotic: String, Codable { case moxifloxacin = "Moxifloxacin", ertapenem = "Ertapenem", cefazolin = "Cefazolin" }
enum HemorrhageRx: String, Codable { case txa = "TXA" }
enum FluidProduct: String, Codable {
    case lr = "Lactated Ringer's", ns = "Normal Saline"
    case wholeBlood = "Whole Blood", plasma = "Plasma", rbc = "RBC"
}
enum Route: String, Codable { case iv = "IV", im = "IM", io = "IO", inRoute = "IN", po = "PO", otfc = "OTFC" }

struct MedAdmin: Codable {
    var name: String
    var dose: String?
    var route: Route?
    var time: String?
    var sourceText: String?      // raw transcript snippet for human verification
}
```

### 4.3 Templates

```swift
struct NineLine: Codable {
    var location: String?           // 8-digit grid
    var freqCallsign: String?
    var precedence: PrecedenceCounts?
    var equipment: [String]?        // ["None","Hoist","Extraction","Ventilator"]
    var litterCount: Int?
    var ambulatoryCount: Int?
    var security: String?           // "No Enemy"|"Possible Enemy"|"Enemy in Area"|"Escort Required"
    var marking: String?            // "Panels"|"Pyro"|"Smoke"|"None"|"Other"
    var nationality: String?        // "US Military"|"US Civilian"|"Non-US Mil"|"Non-US Civ"|"EPW"
    var nbcOrTerrain: String?
}

struct PrecedenceCounts: Codable {
    var urgent: Int?
    var urgentSurgical: Int?
    var priority: Int?
    var routine: Int?
    var convenience: Int?
}

struct ZMIST: Codable {
    var zapNumber: String?
    var mechanism: Mechanism?
    var timeOfInjury: String?       // "HH:MM"
    var primaryInjury: Injury?
    var bodyLocation: String?
    var avpu: AVPU?
    var pulse: PulseStrength?
    var respRate: Int?
    var spo2: Int?
    var classification: Stability?
    var tourniquets: [Tourniquet] = []
    var meds: [MedAdmin] = []
    var interventions: [String] = []
    var uncertainSpans: [String] = []
}

struct Tourniquet: Codable {
    var type: String?               // "Extremity"|"Junctional"|"Truncal"
    var location: String?
    var time: String?
}

struct DD1380: Codable {
    var battleRoster: String?       // initials + last4
    var evacPriority: EvacPriority?
    var name: String?               // "Last, First"
    var allergies: String?          // "NKDA" if none
    var vitals: [VitalsRow] = []
    var tqApplied: [String] = []    // "Extremity"|"Junctional"|"Truncal"
    var dressings: [String] = []    // "Hemostatic"|"Pressure"|"Other"
    var airway: String?             // "Intact"|"NPA"|"CRIC"|"ET-Tube"|"SGA"
    var breathing: [String] = []    // "O2"|"Needle-D"|"Chest-Tube"|"Chest-Seal"
    var fluids: [MedAdmin] = []
    var meds: [MedAdmin] = []
    var notes: String?
}

struct VitalsRow: Codable {
    var time: String?
    var pulse: String?
    var bp: String?
    var rr: String?
    var spo2: String?
    var avpu: String?
    var pain: Int?
}
```

### 4.4 Slot-Filler Logic Rules (Hard-Coded)

These run after every model emission, before committing to the store:

1. **Unstable override.** If `spo2 < 92` (or `< 90` non-TBI), or `avpu != .alert`, or `pulse ∈ {.weak, .absent}`, or `respRate > 30`, force `classification = .unstable`. This overrides any model-emitted `.stable`.
2. **TQ requirement.** If `mechanism == .gsw` with massive-hemorrhage cues OR `primaryInjury ∈ {.massiveHemorrhage, .amputation}`, scan transcript for tourniquet entries and prompt the next model pass with `Keywords: tourniquet, time applied`.
3. **Field locking.** Once a field's confidence ≥ 0.85, lock it. Conflicting subsequent emissions go to `uncertainSpans`, never overwrite.
4. **Source attribution.** Every committed field stores the originating transcript snippet for human review.
5. **Silence handling.** Missing mandatory fields emit `nil` — never guess. UI shows `nil` as `"NOT_HEARD"`.

---

## 5. Phases

Ordered. Each phase ends with autonomous verification (no asking Mike for screenshots). Each phase commits with the message format in §9.

### Phase 0 — Repo recon & dependency wiring
**Goal:** Inventory the repo, add MLX-Swift, prepare scaffolding.

**Tasks:**
1. Run `find . -name "*.swift" | head -40`, `cat Package.swift` (or inspect `.xcodeproj`), `cat Info.plist`. Emit `PHASE_0_RECON.md`.
2. Add SwiftPM dependencies:
   - `https://github.com/Blaizzy/mlx-audio-swift` — the audio path (`MLXAudioSTT`, `MLXAudioCore`).
   - `https://github.com/ml-explore/mlx-swift` — core tensor ops, used by mlx-audio-swift transitively but worth pinning explicitly.
   - Pin both to a known-working tag — fetch the latest release tag of each and pin to that. Document the exact commits in `TCCCAudioLLM/CLAUDE.md`.
3. Add `NSMicrophoneUsageDescription` to `Info.plist`: `"TCCC.ai uses the microphone to capture casualty-care narration for on-device structured documentation."`
4. Create directory `TCCCAudioLLM/` with subfolders: `Audio/`, `Templates/`, `Inference/`, `UI/`, `Resources/`, `Tests/`.
5. Create empty `TCCCAudioLLM/CLAUDE.md` for sub-context.

**Verification:**
- `xcodebuild -scheme <existing-scheme> -destination 'generic/platform=iOS' build` succeeds.
- `swift package resolve` succeeds.
- New folders exist; existing sign-in flow files are untouched (`git diff --stat` shows only additions).

**Commit:** `phase 0: tccc audio-llm scaffolding + mlx-swift deps`

---

### Phase 1 — Templates + state machine (no audio, no model)
**Goal:** Pure-Swift, fully unit-testable template layer.

**Tasks:**
1. Implement the structs and enums from §4 in `TCCCAudioLLM/Templates/`.
2. Implement `TemplateStore: ObservableObject` with `@Published var nineLine`, `zmist`, `dd1380`. Methods: `commit(field:value:confidence:source:)`, `lock(field:)`, `flagUncertain(span:)`.
3. Implement `SlotFillerRules` enforcing the five hard-coded rules from §4.4.
4. Implement `MockExtraction` — a struct that emits canned partial-JSON slices simulating model output, so the store can be tested end-to-end without a model.
5. Write `TemplateStoreTests` exercising: the unstable override, field locking on conflicting roster numbers, source attribution preservation, partial-JSON merging.

**Verification:**
- `xcodebuild test -scheme <test-scheme>` passes all `TemplateStoreTests`.
- All five slot-filler rules have at least one passing test.

**Commit:** `phase 1: tccc templates + slot-filler state machine`

---

### Phase 2 — Audio engine (gain metering, no model)
**Goal:** Working `AVAudioEngine` capture with metering and 16 kHz mono resampling.

**Tasks:**
1. Implement `TCCCAudioManager: ObservableObject` in `TCCCAudioLLM/Audio/`. Use `AVFoundation` (**not** `AVAudioKit` — Gemini's reference snippet has the wrong import).
2. Properties: `@Published var inputLevelDb: Float`, `@Published var appliedGain: Float`, `@Published var isRecording: Bool`.
3. Install a tap on a mixer node. Compute RMS → dBFS per buffer. Apply makeup gain: if `db < -30`, multiply samples by 2.0; clamp to avoid clipping.
4. Resample tapped audio to 16 kHz mono `Float32` via `AVAudioConverter`. Push into a thread-safe ring buffer (`TCCCAudioRingBuffer`) sized for 4-second chunks (Granite Speech encoder block size).
5. Wrap session lifecycle in `UIBackgroundTaskIdentifier` so screen lock doesn't kill it.
6. Configure `AVAudioSession` category `.record`, mode `.measurement`, options `.mixWithOthers`.
7. Implement `AudioMemoryReporter.residentGB()` using `mach_task_basic_info` (Gemini's snippet is correct here; preserve it).

**Verification:**
- `xcodebuild test`: a unit test feeds a known sine wave through the resampler, asserts output is 16 kHz mono and RMS matches expected ±5%.
- `xcodebuild build` succeeds with no warnings on `import AVFoundation`.
- Manual smoke (autonomous): `xcrun simctl spawn booted log show --predicate 'category contains "TCCCAudio"'` shows expected lifecycle messages after a 5-second `startCapture()` → `stopCapture()` cycle.

**Commit:** `phase 2: avaudioengine capture + gain metering + 16khz resample`

---

### Phase 3 — Model bundling + load path (no live audio yet)
**Goal:** Bundled Granite Speech weights load via `mmap` and run a single fixed-audio inference end-to-end.

**Tasks:**
1. **Procure the model — two-track approach.**
   - **Track A (default, ships):** Pull `mlx-community/granite-4.0-1b-speech-8bit` via `huggingface-cli download`. This artifact already exists, was converted via mlx-audio v0.4.0, and works with the `MLXAudioSTT` Swift module. Place under `TCCCAudioLLM/Resources/models/granite-4.0-1b-speech-8bit/`. Add to Xcode target with **Embed & Sign**.
   - **Track B (stretch, parallel):** On a Mac dev machine, run `python -m mlx_audio.convert --hf-path ibm-granite/granite-speech-4.1-2b --mlx-path ./granite-4.1-2b-mlx --quantize --q-bits 8` to produce a 4.1 2B MLX bundle. If conversion succeeds and the resulting weights load+run cleanly through `MLXAudioSTT`, swap Track A for Track B and document the upgrade in `TCCCAudioLLM/CLAUDE.md`. If conversion fails or runtime errors out, ship Track A and file an issue against Blaizzy/mlx-audio. **Do not block the sprint on Track B.**
2. **Validate the Swift API before writing the loader.** Open `mlx-audio-swift` and confirm the current `MLXAudioSTT` model loader signature for Granite Speech. The Python-side idiom is `model = load_model("mlx-community/granite-4.0-1b-speech-8bit")` then `generate_transcription(model=, audio=, ...)`; the Swift-side equivalent is what to write the loader against. Pin the API version in `TCCCAudioLLM/CLAUDE.md`.
3. Implement `TCCCSynthesisEngine` in `TCCCAudioLLM/Inference/`:
   - `init()` loads the model via `MLXAudioSTT`'s loader (fail-fast if model files missing).
   - `loadModel() async throws` — mlx-swift defaults to `mmap` for safetensors; verify and document.
   - `extractFromAudio(_ pcm: [Float], sampleRate: Int) async throws -> String` returns a JSON string. Use Granite Speech's chat-template path (see IBM model card vLLM example) with keyword biasing: a system-style instruction asking for the four-template JSON schema, plus a `Keywords:` line covering TCCC vocabulary. Initial prompt:
     ```
     <|audio|>Extract TCCC documentation as a single JSON object matching:
     {"nine_line": {...}, "zmist": {...}, "dd1380": {...}}
     Fields not heard must be null. Never guess. Output ONLY the JSON object.
     Keywords: tourniquet, TXA, GSW, AVPU, SpO2, MEDEVAC, DD1380, ZMIST, 9-line, MARCH, hemorrhage, pneumothorax, ketamine, fentanyl, morphine, moxifloxacin, ertapenem, cefazolin, hextend, lactated ringer's, whole blood, plasma, needle decompression, chest seal, NPA, cric.
     ```
   - **Empirical decision point:** if the raw output parses as valid JSON with reasonable field population on the 5-minute fixture, single-pass extraction is the production path. If output is malformed or JSON-shaped but mostly null, document the failure mode in `PHASE_3_RESULTS.md` and Phase 4 adds the two-pass fallback (Granite Speech transcript → granite-4.0-1b-base text LLM → JSON, using the same in-bundle weights via the disable-adapter pattern). **Do not preemptively build the two-pass path in Phase 3.** First find out what actually works.
4. Bundle the 5-minute test narrative as a `.wav` file (16 kHz mono) in `TCCCAudioLLM/Resources/test_audio/`. Generate it autonomously via `say -o test_5min.aiff "..." && afconvert ... 16000` from the narrative text in §6, OR commit a synthesized version using `AVSpeechSynthesizer` in a one-shot Xcode helper target.
5. Implement `RAMGauge` view (SwiftUI) bound to `AudioMemoryReporter.residentGB()` polled at 1 Hz.

**Verification:**
- `xcodebuild test` runs a `ModelLoadTests` case that:
  - Loads the model container (asserts `< 5s` on simulator; record actual on device in `CLAUDE.md`).
  - Asserts resident memory delta `< 1.5GB` post-load on iPhone 17 Pro for Track A (4.0 1B INT8); `< 2.5GB` if Track B succeeded (4.1 2B INT8).
  - Runs `extractFromAudio` against the bundled 5-min test fixture.
  - Categorizes the output: (a) parses as valid JSON, (b) JSON-shaped but field population poor, (c) free-form text. Test passes regardless — this phase is about characterization, not asserting JSON quality. Quality assertions land in Phase 4.
- Emit `PHASE_3_RESULTS.md` with: which track shipped, load time, post-load resident memory, single-pass inference time, raw output snapshot, output category, and recommendation for Phase 4 (single-pass vs. two-pass).

**Commit:** `phase 3: granite speech mlx load + single-pass extraction characterization`

---

### Phase 4 — Live inference loop + slot filler integration
**Goal:** Wire streaming audio chunks into the model and asynchronously update the `TemplateStore`.

**Tasks:**
1. In `TCCCSynthesisEngine`, add `processChunk(pcm: [Float]) async`. Buffer ~4-second chunks (Granite's encoder block size). Maintain rolling text-summary context of already-extracted fields and inject into the prompt for each new chunk (Gemini's "context stitching" strategy — keeps KV cache from ballooning across a 5-minute narration).
2. Implement constrained JSON generation. Two acceptable paths — pick whichever the current `mlx-swift` build supports cleanest, document the choice:
   - **Preferred:** Schema-guided sampling using mlx-swift logit processors, with a precomputed FSM derived from the Codable struct schemas.
   - **Acceptable fallback:** Plain generation + strict `JSONDecoder` validation; on parse failure, retry with a clearer "valid JSON only" suffix; on second failure, log to `uncertainSpans` and continue.
3. Wire the audio ring buffer (Phase 2) → `processChunk` → JSON parse → `SlotFillerRules.apply(...)` → `TemplateStore.commit(...)`. Run inference on a dedicated `Task.detached(priority: .userInitiated)`.
4. Implement KV cache pruning: when `AudioMemoryReporter.residentGB() > 3.5`, discard oldest 25% of cached prompt tokens (keep system prompt + most recent context). Log the prune event.
5. Implement an 8-bit KV cache config flag where the mlx-swift API exposes one; otherwise document as deferred and note in `TCCCAudioLLM/CLAUDE.md`.
6. **Speculative decoding (optional, defer if time-constrained):** IBM published a self-speculative decoding paper specifically for this model family — "Self-Speculative Decoding for LLM-based ASR with CTC Encoder Drafts" (arXiv 2603.11243), with an official notebook at `ibm-granite/granite-speech-models/notebooks/speculative_decoding_bpe.ipynb`. The approach uses the CTC encoder's intermediate hypothesis as drafts — strictly better than running a separate small text model as a draft pair (no extra audio pass, no separate weights, validated by IBM). If `mlx-audio-swift` exposes a hook for this, wire it; if not, log as a deferred optimization in `TCCCAudioLLM/CLAUDE.md` and move on. **Do not run a separate Granite 4.0 350M as a draft model — that approach was suggested in upstream research notes but is inferior to IBM's self-speculative method.**

**Verification:**
- `xcodebuild test` `LiveLoopTests`:
  - Feeds the 5-min test fixture via the ring buffer (synthetic real-time playback through `AVAudioPCMBuffer` injection — no actual mic).
  - After full playback, asserts `zmist.mechanism == .gsw`, `zmist.classification == .unstable` (must be set by the unstable-override rule, even if model emits `.stable`), `nineLine.location` contains `"8734"` and `"9120"`, `dd1380.battleRoster` contains `"6942"`, `zmist.meds` contains a `MedAdmin` with `name == "TXA"`.
  - Asserts no field was overwritten after locking (insert a deliberate conflicting roster mid-stream and assert it lands in `uncertainSpans`).
- Emit `PHASE_4_RESULTS.md` with field-by-field expected-vs-actual table.

**Commit:** `phase 4: streaming inference + slot filler + kv prune`

---

### Phase 5 — SwiftUI integration
**Goal:** Single screen showing recording state, gain reactivity, RAM, and live template population.

**Tasks:**
1. `TCCCRecordingView`:
   - Top: large red/grey record button bound to `audioManager.isRecording`.
   - Waveform strip: 60-frame rolling buffer of `inputLevelDb`, two overlaid traces — pre-gain (grey) and post-gain (cyan, per Mike's Tokyo Night Storm preference). Use `Canvas` for drawing.
   - Gain gauge: numeric `appliedGain` with a small bar (1.0× to 4.0× range).
   - RAM gauge: numeric GB + thin bar; color-shifts to amber at 3.0GB, red at 3.5GB.
2. `TCCCTemplateView`: three collapsible sections (9-Line, ZMIST, DD1380). Each field renders with three states:
   - `nil` → grey placeholder text `"NOT_HEARD"`.
   - Pending (confidence < 0.85) → italic, dimmed.
   - Locked → solid, with a small lock glyph and tap-to-reveal source snippet.
3. `TCCCGenerateScriptButton`: emits a plain-text rendering of the current state machine — the "accurate-looking script" Mike asked for. Copy to clipboard + share sheet.
4. Wire the existing repo's root navigation so the recording view is reachable post-sign-in. Do not modify any sign-in code.

**Verification:**
- `xcodebuild build` for both Debug and Release succeeds.
- Snapshot test (`PreviewTests`) renders `TCCCRecordingView` with three template fixture states (empty, partial, full) and compares to bundled reference PNGs.
- Autonomous simulator run: `xcrun simctl boot`, install app, launch, send a synthesized audio file via simulator audio injection (`xcrun simctl io booted recordVideo`-equivalent for audio is limited — fall back to a debug-only "Replay test fixture" button gated by `#if DEBUG`).

**Commit:** `phase 5: swiftui recording + template view + script export`

---

### Phase 6 — End-to-end smoke
**Goal:** One reproducible E2E run against the 5-minute fixture, committed as a baseline.

**Tasks:**
1. Add UI test target if absent. Write `E2ETest` that:
   - Launches the app in a test mode that bypasses sign-in (debug-only flag — verify with Mike before shipping; for now, gate behind `#if DEBUG && TCCC_E2E`).
   - Triggers "Replay test fixture."
   - Waits for the script-export button to enable.
   - Asserts the exported text contains all expected fields from §6.
2. Emit `E2E_BASELINE.md` with timing, peak RAM, and field-coverage percentage.

**Verification:**
- `xcodebuild test -scheme <ui-test-scheme> -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` passes.
- `E2E_BASELINE.md` shows ≥ 90% field coverage on the fixture (per Gemini's transcript design — 90% of the data is in there).

**Commit:** `phase 6: e2e smoke + baseline`

---

## 6. Bundled Test Fixture (5-Minute Narrative)

Save as `TCCCAudioLLM/Resources/test_audio/test_5min.txt` and synthesize to `test_5min.wav` (16 kHz mono) at build time (or one-shot, then commit the wav).

```
[00:00 - 00:30] BREAK, BREAK! This is Medic Kilo-6. I have a MEDEVAC request! Grid coordinate Eight-Seven-Three-Four, Niner-One-Two-Zero. I repeat: 8734 9120. Frequency is 44.50, Call-sign Reaper. We have one Urgent Surgical, GSW to the chest. Over!

[00:30 - 01:30] Casualty is US Military, Battle Roster Romeo-Delta-Six-Niner-Four-Two. Name is Dawson, Robert. Last four is 6942. Dawson, stay with me! He's got NKDA, no allergies. Mechanism was Small Arms Fire, single GSW to the upper right chest. Time of injury was 14:02 Local.

[01:30 - 03:00] Check his pulse. Radial is weak, barely there. He's breathing fast, maybe 32 a minute. SpO2 is dropping, we're at 88%. AVPU is P, he's only responding to pain. He's unstable. Mark the DD1380: Vitals taken at 14:10. Heart rate 135, BP is 88 over 60.

[03:00 - 04:30] I'm applying a vented chest seal to that exit wound now. Breathing is still labored. I'm moving to a Needle Decompression, right side, second intercostal space. Okay, air hiss noted. SpO2 coming back up to 93%. I'm initiating a saline lock. Giving one gram of TXA over ten minutes. Also starting 500mL of Hextend since the radial pulse is still weak.

[04:30 - 05:00] Pickup site is secure, no enemy in the area. Marking with green smoke. Casualty is US Military. HLZ is a flat clear-cut, no obstacles. Medic Kilo-6, out!
```

**Expected extraction (acceptance baseline):**
- `nineLine.location` ≈ `"87349120"`, `nineLine.freqCallsign` ≈ `"44.50 Reaper"`, `nineLine.precedence.urgentSurgical == 1`, `nineLine.security == "No Enemy"`, `nineLine.marking == "Smoke"` (green), `nineLine.nationality == "US Military"`.
- `zmist.mechanism == .gsw`, `zmist.timeOfInjury == "14:02"`, `zmist.primaryInjury == .torsoTrauma`, `zmist.bodyLocation` mentions chest, `zmist.avpu == .pain`, `zmist.pulse == .weak`, `zmist.respRate == 32`, `zmist.spo2` initial `88`, final `93`, `zmist.classification == .unstable` (forced by override rule), `zmist.interventions` includes chest seal + needle decompression, `zmist.meds` includes `TXA` with dose `1g` and Hextend.
- `dd1380.battleRoster ≈ "RD6942"`, `dd1380.name == "Dawson, Robert"`, `dd1380.allergies == "NKDA"`, `dd1380.evacPriority == .urgentSurgical`, vitals row at `14:10` with HR 135, BP 88/60.

---

## 7. Known Issues in Reference Snippets (Pre-Flight Cleanup)

The Gemini snippets in the source document contain three landmines. Address all three in the relevant phase, do not propagate them:

1. **`import AVAudioKit` is wrong.** Use `import AVFoundation`. (Phase 2.)
2. **`LLMModelContainer.load(path:quantization:)` is pseudo-code.** The real `mlx-swift` / `mlx-swift-examples` API is different. Validate the current API against the pinned commit before writing the loader. (Phase 3.)
3. **`processAudioForModel(buffer: gain:)` is referenced but never defined.** Implement it as the resampler+ring-buffer push described in Phase 2 task 4.

Also: Gemini's snippet applies `appliedGain` on the audio thread but reads it via the main-queue dispatch. That's a race. In the real implementation, store the gain in an `OSAllocatedUnfairLock`-guarded value (or an atomic), update from the audio thread directly, and let SwiftUI observe via a `@Published` updated on the main thread separately.

### 7.1 Errors in Subsequent Research Notes (Verified Wrong)

A separate "model links" deep-research turn returned three claims that don't survive verification. Documenting here so they don't leak back into the implementation:

1. **`cstr/granite-speech-4.1-2b-GGUF` is not the deployment artifact.** GGUF is llama.cpp's format. Our stack is `mlx-audio-swift` / `mlx-swift`, which uses MLX-native safetensors. The right path is `mlx-community/granite-4.0-1b-speech-8bit` (already exists) or self-conversion of `ibm-granite/granite-speech-4.1-2b` BF16 safetensors via `mlx_audio.convert`. The "hybrid q4_k preserves encoder precision" claim is also fabricated — GGUF quantization doesn't selectively preserve sub-modules of unified speech-LMs that way.
2. **`mlx-vlm` is not the right framework for Granite Speech.** mlx-audio is the maintained path: PR #565 added Granite Speech 4.0 to mlx-audio, the existing `mlx-community/granite-4.0-1b-speech-{5bit,8bit}` artifacts were converted via mlx-audio v0.4.0, and mlx-audio's README explicitly points iOS work to mlx-audio-swift. mlx-vlm is for vision-language models.
3. **Granite 4.0 350M as a draft pair is inferior to IBM's published self-speculative method** — see Phase 4 task 6.

---

## 8. Fallback Paths

| If… | Then… |
|---|---|
| Track B (Granite Speech 4.1 2B self-conversion via `mlx_audio.convert`) fails or runtime errors | Stay on Track A (`mlx-community/granite-4.0-1b-speech-8bit`). 0.2 WER cost, otherwise the same architecture family. Document in `CLAUDE.md`. |
| Granite Speech is too heavy on iPhone 17 Pro under thermal load | Drop to the 5-bit variant `mlx-community/granite-4.0-1b-speech-5bit`. If still too heavy, last-resort switch to Canary-Qwen-2.5B INT4 (~1.6GB). Re-validate FastConformer adapter bridge (NeMo→MLX is non-trivial — flag as a 2-day side-quest, do not absorb into the sprint). |
| `mlx-audio-swift` lacks a Granite Speech STT module path on iOS | Halt and emit `BLOCKED:`. Two recovery options to discuss with Mike: (a) use the Python `mlx-audio` library on the Mac dev side and a thin local network bridge for iPhone testing only; (b) add the Granite Speech path to `mlx-audio-swift` directly via PR. Both are out of sprint scope. |
| Single-pass JSON extraction (Phase 3) produces malformed output | Fall through to two-pass: Granite Speech transcript → granite-4.0-1b-base text LLM → JSON, using disable-adapter pattern on the same loaded weights. Document in Phase 4 as the production path. |
| Constrained JSON generation isn't supported in current mlx-swift | Use plain generation + strict `JSONDecoder` + retry-once + fall-through to `uncertainSpans`. Do not block the phase. |
| Bundling weights blows past App Store size limits during dev | Use on-demand resources (`NSBundleResourceRequest`) only as a last resort, since this directly contradicts Mike's "no remote download" requirement. Halt and emit `BLOCKED:` first. |
| `xcodebuild test` flakes in CI but passes locally | Document the flake, mark the test `XCTSkip`-on-CI, do not delete. |

---

## 9. CLAUDE.md Merge Protocol

- **Root `CLAUDE.md`** (existing repo): append-only. Add a new section `## TCCC Audio-LLM Subsystem` with a one-paragraph summary and a link to `TCCCAudioLLM/CLAUDE.md`. Do not modify existing sections.
- **`TCCCAudioLLM/CLAUDE.md`** (new): the working journal for this subsystem. Each phase appends a dated section: locked decisions made during execution, API versions pinned, performance numbers measured, anything Mike will need to recall in three months.
- Never delete from `CLAUDE.md`. To supersede a prior note, append a `[SUPERSEDED YYYY-MM-DD: ...]` line below it.

---

## 10. Commit Message Format

```
phase N: <verb> <subject>

- bullet of what landed
- bullet of what was deferred
- bullet of any BLOCKED: items

Token budget: <consumed>/200K
Files changed: <count>
```

Per Mike's git rule: work directly on `main`, no new branches. The post-commit auto-push hook is on his RPi5 globally (and queued for MBP); do not assume it's installed in this repo's host. Run `git push origin main` explicitly at end of each phase.

---

## 11. Final Acceptance Criteria

The sprint is done when, on a clean iPhone 17 Pro device:

1. App launches via existing sign-in.
2. Recording view appears, mic permission granted via the prompt added in Phase 0.
3. Pressing record causes the cyan post-gain trace to react to live speech within 100ms.
4. RAM gauge stays under 3.5GB across a continuous 5-minute recording.
5. Within 60 seconds of speech-end, the three template panels show populated fields with at least one source snippet revealed on tap.
6. The "Generate Script" button produces a plain-text export covering all locked fields.
7. `git log --oneline | head -7` shows seven phase commits, each with the format in §10.

If a criterion can't be met, halt and emit `BLOCKED:` — do not partial-deliver and label it complete.

---

## 12. Out of Scope (Explicitly)

- Google Drive upload (Gemini offered to refine this; not part of this sprint).
- Encrypted-at-rest storage of generated documents (next sprint).
- Multi-casualty MASCAL handling (one casualty at a time for this prototype).
- Translation / multilingual (Granite supports it; English-only for sprint 1).
- ATAK plugin packaging (Gemini asked; answer is standalone app for now).
- The Canary-Qwen FastConformer→MLX adapter port (parked as fallback only).

---

*End of spec. Feed this whole document to Claude Code in the TCCC iOS repo, one phase at a time, with `Read SPRINT_TCCC_AUDIO_LLM.md and execute Phase N.`*
