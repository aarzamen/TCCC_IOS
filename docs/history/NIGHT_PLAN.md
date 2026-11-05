# Night plan — 2026-05-05 → 2026-05-06 (second pass)

This is the durable execution doc for the second overnight pass. Mike
asked for: Parakeet ASR ported in modular fashion with ring buffer for
near-real-time, kept as ALT fallback (Apple Speech remains default);
Qwen / Liquid LFM2 backend scaffold for the LLM side, also alt
fallback; Zulu+Lima dual time; MGRS instead of lat/long; RAM pressure
indicator near time; default theme flip (Tactical → Dark); Foundation
Model "still downloading" warning fix.

Plan is laid out so a future me — possibly post-context-compaction —
can pick up where it stopped. Each task names the files involved and
the verification step.

## Conventions for this pass

- All work on `main`. Commit per logical chunk; push at end.
- Apple Speech ASR + Apple Foundation Models stay as defaults. New
  backends are opt-in via Settings.
- "On ice" = code committed and compiling, behind a feature flag;
  no model weights bundled; runtime calls return a deterministic stub
  until the operator flips a switch and provides the model.
- 653 TCCCKit tests + xcodebuild build are the verification battery.
  Phase boundaries run both. No `[WIP]` commits unless I hit a true
  blocker.

## Track A — UI quality of life (sequential, fastest wins)

### A1: Dual time display in StatusStrip
**File:** `TCCC_IOS/Chrome/StatusStrip.swift`
**What:** Replace the session-elapsed `recCell.elapsedTimer` with a
`HH:mm Z / HH:mm L` dual display where:
  - Z = Zulu (UTC) — `formatter.timeZone = .gmt`
  - L = Lima (Local) — system locale
The session-elapsed counter moves to the casualty cell as a sub-line
("C-04 · 14:32 elapsed") so it isn't lost.
**Verify:** screenshot the simulator; build green.

### A2: MGRS conversion + display
**Files:**
- New: `Packages/TCCCKit/Sources/TCCCDomain/MGRS.swift`
- Updated: `TCCC_IOS/Chrome/StatusStrip.swift` (if a small MGRS chip
  takes the freed area), `Packages/TCCCKit/Sources/TCCCReports/MedevacGenerator.swift`
  (LINE 1 location), `TCCC_IOS/Screens/HandoffScreen.swift` (encounter summary)

**What:** WGS-84 lat/lon → MGRS string (e.g. `42S WD 12345 67890`).
Background agent will research existing Swift MGRS implementations;
otherwise I implement it from the standard formulas (UTM zone +
band letter + 100km grid square + easting/northing). MGRS is
display-only — the underlying lat/lon stays the source of truth in
`AppState`.

**Verify:** unit test with a known coordinate (e.g. 34.5267°N
69.1729°E should yield a specific MGRS — agent will confirm).

### A3: RAM pressure / used indicator
**Files:**
- New: `TCCC_IOS/App/MemoryStat.swift`
- Updated: `TCCC_IOS/Chrome/StatusStrip.swift` (compact chip near battery)

**What:** Show available memory or used % via
`os_proc_available_memory()` (returns bytes available before iOS
jetsam) or `task_info()` for current resident size. Compact display:
e.g. `1.2 G` or `78%`. Update on a Timer at 1Hz.

**Verify:** simulator value visible; doesn't block the UI thread.

### A4: Default theme: Tactical → Dark
**File:** `TCCC_IOS/App/AppState.swift`, line `var theme: Theme = .tactical`.
Change initial value to `.dark`. Tactical remains selectable in
Settings — only the default flips.

**Verify:** fresh build opens to Dark; theme picker still works.

### A5: Foundation Model availability persistent badge
**Files:**
- Updated: `TCCC_IOS/Intelligence/TCCCLanguageModel.swift` (cache the
  current `availability` value with a 5s refresh)
- New: `TCCC_IOS/Components/FMStatusBadge.swift` — compact chip
  showing `SLM · ready` / `SLM · downloading` / `SLM · disabled` /
  `SLM · device n/a`
- Updated: `TCCC_IOS/Screens/HandoffScreen.swift`,
  `TCCC_IOS/Screens/MedevacScreen.swift` to surface the badge near
  the Generate buttons

**What:** Replace the one-shot error pop with a persistent state
indicator the medic sees BEFORE tapping Generate. If the model is
still downloading, badge says so and the button stays disabled.
Once `.available`, badge flips green and Generate is tappable.

**Verify:** simulator shows the badge transition; failure paths
don't crash.

## Track B — Parakeet ASR (fallback, "on ice")

Reference: `RESEARCH_PARAKEET.md` from the previous overnight pass.
Recommended model: `parakeet-tdt-0.6b-v2` (English, CC-BY-4.0 via
NVIDIA) packaged for CoreML by `FluidInference/FluidAudio` (Apache
2.0 Swift SDK). Runs on the Apple Neural Engine.

### B1: Add FluidAudio SPM dependency
**File:** `project.yml`
**What:** Add `https://github.com/FluidInference/FluidAudio.git` as a
package dep, link `FluidAudio` product to the `TCCC_IOS` app target.
Run `xcodegen generate` and confirm Package.resolved updates.

**Verify:** xcodebuild build green; the FluidAudio module is
importable from a placeholder file.

### B2: Model bundle / download strategy
**Decision:** download on first activation, NOT bundled.
The CoreML build is ~300 MB. Bundling pushes the SideStore IPA over
practical sizes and forces every install to ship weights even if
the user never enables Parakeet. Strategy:
1. Settings switch "Use Parakeet ASR (alt)" — defaults OFF.
2. First time the switch flips ON, prompt the user for one of:
   (a) AirDrop the model file from Mac (URLSession-free)
   (b) Tap "Download" — single HTTPS GET from a user-controlled
       URL. This is the ONLY networking the app ever does, gated
       behind explicit user consent. RF Ghost is preserved post-download.
3. Cached at `Documents/parakeet/` with `NSFileProtectionComplete`.
4. Hash-verified on load (SHA-256 of model bundle).

**Files:**
- New: `TCCC_IOS/App/ParakeetModelStore.swift` — handles the
  AirDrop / download / hash-verify lifecycle.
- Updated: `TCCC_IOS/Components/SettingsOverlay.swift` — adds the
  toggle and the "Provide model file" UI.

**Verify:** the toggle is reachable in Settings; default is OFF;
flipping ON without a model file shows the file-source prompt.

### B3: ParakeetTranscriptStream actor
**File:** `TCCC_IOS/Audio/ParakeetTranscriptStream.swift`
**What:** Conforms to the existing `TranscriptStream` protocol.
Wraps FluidAudio's `StreamingEouAsrManager` (preferred — built for
streaming with end-of-utterance detection) or `SlidingWindowAsrManager`
(simpler, less responsive).

```swift
actor ParakeetTranscriptStream: TranscriptStream {
    private var manager: StreamingEouAsrManager?
    private let leadDuration: TimeInterval = 30.0
    private let tailDuration: TimeInterval = 30.0
    private var ringBuffer: [AVAudioPCMBuffer] = []
    // ... mirrors SpeechRecognizer's lifecycle
    func prime() async throws { /* warm engine + tap */ }
    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> { ... }
    func stop() async { /* schedule 30s tail */ }
    func unprime() async { /* engine + tap off */ }
    func forceFinalize() async { /* boundary commit */ }
}
```

**Verify:** unit test with a fake audio buffer + a fake FluidAudio
manager (use a protocol abstraction so we can inject a stub in
tests). The real model isn't bundled in CI; runtime test happens
on device only.

### B4: Ring buffer for near-real-time
The 30s pre-roll already exists in `SpeechRecognizer`. The new actor
mirrors the same `[AVAudioPCMBuffer]` ring + `frameCount` eviction.
The streaming path then drains the ring into FluidAudio's manager
on `start()` so the medic gets pre-tap context indexed correctly.

### B5: Backend selection in AppState
**File:** `TCCC_IOS/App/AppState.swift`
```swift
enum ASRBackend: String, Sendable, CaseIterable {
    case appleSpeech     // default
    case parakeet        // alt, on ice
}
var asrBackend: ASRBackend = .appleSpeech
```
The recognizer is owned by `LiveCaptureScreen`'s view-model. Make
that own a `(any TranscriptStream)?` and lazily instantiate based on
`state.asrBackend`. When the toggle flips, tear down the current
backend and rebuild.

### B6: On-device verification
Build, install via `xcrun devicectl`, exercise both backends in
landscape with a memorized scenario. Capture qualitative WER notes
in `RESEARCH_PARAKEET.md` or a follow-up doc.

### B7: Mark "on ice"
Default is `.appleSpeech`. Parakeet is invisible until the operator
flips the Settings toggle. Code stays in the binary; the model
weights do not. Future: bundle once field-tested.

## Track C — Qwen / Liquid LFM2 LLM scaffold (also "on ice")

Reference: `RESEARCH_LLAMA32B.md` from the previous overnight pass —
flagged Llama 3.2 3B as oversize for iPhone 17 Pro jetsam AND under
an AUP that prohibits medical/military use. Pivot: Qwen 3 1.7B
(Apache 2.0) and Liquid AI's LFM2 family (research-pending license).

### C1: Liquid LFM2 vs Qwen 3 1.7B research (parallel agent)
The agent will write `RESEARCH_LLM_SMALL.md` covering:
  - LFM2 model variants (1B, 3B available on Hugging Face)
  - License (Apache 2.0? LFM Open Use License? — agent will confirm)
  - Memory profile at 4-6 bit quant on A19 Pro
  - Throughput vs Qwen 3 1.7B
  - Integration via `mattt/AnyLanguageModel` or `tattn/LocalLLMClient`

### C2: TCCCLLMBackend protocol
**Files:**
- New: `TCCC_IOS/Intelligence/TCCCLLMBackend.swift` — protocol
- New: `TCCC_IOS/Intelligence/AppleFoundationLLM.swift` — current
  Foundation Model wrapped in the protocol
- New: `TCCC_IOS/Intelligence/QwenLLM.swift` — stub
- New: `TCCC_IOS/Intelligence/LFM2LLM.swift` — stub

The protocol shape mirrors the four use cases the existing
`TCCCLanguageModel` covers:
```swift
protocol TCCCLLMBackend: Sendable {
    func generateRadioScript(from form: NineLineForm, callsign: String) async throws -> String
    func generateNarrative(from patient: PatientState) async throws -> String
    func generateZMIST(from patient: PatientState) async throws -> String
    func cleanTranscript(_ raw: [TranscriptLine]) async throws -> [TranscriptLine]
    var availability: BackendAvailability { get async }
}
```

### C3: Stubbed Qwen / LFM2 backends
Each stub conforms to the protocol but its `generate*` methods
throw `BackendError.notYetImplemented`. The `availability` getter
returns `.unavailable(.modelNotProvided)`. This compiles, ships,
and turns on cleanly when models are bundled later.

### C4: Backend selection
**File:** `TCCC_IOS/App/AppState.swift`
```swift
enum LLMBackend: String, Sendable, CaseIterable {
    case appleFoundation    // default
    case qwen3_1_7b         // alt, on ice
    case lfm2_1b            // alt, on ice
}
var llmBackend: LLMBackend = .appleFoundation
```

### C5: Settings UI for both toggles
The existing SettingsOverlay needs two new sections:
- "ASR backend" — radio between Apple Speech / Parakeet
- "LLM backend" — radio between Apple Foundation / Qwen / LFM2
Each shows a status badge: `READY` / `MODEL NEEDED` / `DEVICE N/A`.

### C6: On ice
Like B7 — default is `.appleFoundation`. Qwen and LFM2 stubs are in
the binary, fail cleanly if invoked, and document the next step
(bundle a Q4-Q6 model and wire MLX-Swift or LocalLLMClient).

## Risk register (re-derived from the last pass)

1. **Memory pressure on iPhone 17 Pro.** Even with 12 GB unified RAM,
   the iOS jetsam ceiling caps a foreground app at ~6 GB. Stacking
   FoundationModel + Parakeet + Qwen would oversubscribe. Mitigation:
   never load more than ONE LLM and ONE ASR backend at a time;
   tear down the inactive one when the toggle flips.

2. **Bundle size.** Parakeet (~300 MB) + Qwen 1.7B Q4 (~1.0 GB) +
   LFM2 1B Q4 (~600 MB) is over 2 GB of weights if all bundled.
   Mitigation: do not bundle weights at all in this pass. First-launch
   download (one URLSession call ever, gated by explicit user
   consent, RF Ghost compliant for the lifetime of the app).

3. **Llama AUP.** Already known — Llama 3.2 forbids medical/military
   use. Qwen (Apache 2.0) and LFM2 (TBD) are the safer paths.
   Mitigation: research agent confirms LFM2 license before any code
   ships referencing the model name in user-facing strings.

4. **xcodegen / SPM dep churn.** Adding FluidAudio + AnyLanguageModel
   (or LocalLLMClient) introduces transitive deps. Mitigation: each
   addition is its own commit; rollback is trivial.

5. **AVAudioEngine resource contention.** Two transcript backends
   wanting the same `AVAudioEngine` won't coexist. Mitigation: only
   one is active at a time per the AppState backend selector.

## Parallelization plan

**Background research agents (dispatched first, run while I work):**
- Agent X: Qwen 3 1.7B vs Liquid LFM2 1B comparative on iPhone 17 Pro
  — license, memory at Q4-Q6, throughput, AnyLanguageModel /
  LocalLLMClient integration. Writes `RESEARCH_LLM_SMALL.md`.
- Agent Y: Swift MGRS conversion — survey existing libraries on
  GitHub (license, accuracy on edge cases like UPS polar zones),
  write `RESEARCH_MGRS.md` with a recommended path.
- Agent Z: iOS RAM pressure / available-memory APIs survey —
  `os_proc_available_memory`, `task_info` MACH_TASK_BASIC_INFO,
  `JetsamMemoryLimit` notifications. Writes a brief
  `RESEARCH_RAM_API.md` with code snippets.

**Foreground sequential (single developer / file-conflict avoidance):**
1. Save plan + memory note (this commit)
2. Track A1 (dual time)
3. Track A2 (MGRS — unblocked once Agent Y returns)
4. Track A3 (RAM indicator — unblocked once Agent Z returns)
5. Track A4 (theme default)
6. Track A5 (FM badge)
7. Build + test + commit Track A
8. Track B1-B7 (Parakeet)
9. Build + test + commit Track B
10. Track C1-C6 (Qwen / LFM2 scaffold — unblocked once Agent X returns)
11. Build + test + commit Track C
12. Final push + status summary

If context compaction happens between any of these steps, pick up
from the last completed task in the git log:
```bash
git log --oneline -10
```
Cross-reference with this plan's task IDs (A1, A2, ... C6) — each
landed commit names its task ID in the subject so resumption is
trivial.

## What I will NOT do tonight

- Bundle any model weights in the IPA (oversize).
- Make any actual network calls (RF Ghost; download UI exists but
  default is OFF).
- Edit the rubric JSONs (clinical ground truth, your authorship).
- Touch signing/distribution/SideStore config.
- Ship a UI for an LLM backend that doesn't actually work — Qwen
  and LFM2 stubs return "not yet implemented" errors so a user
  can't accidentally trust them.
- Break Apple Speech ASR or Apple Foundation Models. They stay
  as the working defaults.

## Wake-up checklist

When you're back at the keyboard:
1. Read the new RESEARCH_*.md files that landed overnight.
2. `git log --oneline -20` to see the night's commits.
3. `cd Packages/TCCCKit && swift test` to confirm green.
4. Open the app on the simulator — see Dark theme, dual time,
   MGRS, RAM chip, FM badge. Then flip Parakeet on in Settings
   and walk through the file-source prompt to see how it feels.

## What actually landed (post-execution log)

All four tracks shipped behind feature flags. Apple Speech and Apple
Foundation Models remain runtime defaults — switching to alt
backends requires explicit operator action that doesn't yet have a
Settings UI.

| Task | Commit | Status |
|------|--------|--------|
| Plan + memory pointers | `d4d099d` | done |
| A1 Z/L dual time | `b68aac4` | done |
| A4 default theme → Dark | `b68aac4` | done |
| A5 SLM persistent badge | `b68aac4` | done |
| B1 FluidAudio SPM dep | `a191828` | done |
| B3 ParakeetTranscriptStream actor | `a191828` | done |
| B5 backend selector + factory | `a191828` | done |
| Research files (parakeet, llama, llm-small, mgrs, ram) | various | done |
| A2 MGRS encoder + 9-line wiring | `eae45ae` | done (rolled own) |
| A3 RAM headroom chip | `eae45ae` | done |
| C2 TCCCLLMBackend protocol | (next) | done |
| C3 Apple/LFM2/Qwen backend stubs | (next) | done |
| C4 AppState.llmBackend enum | (next) | done |

**Deferred to next pass:**
- Settings UI for ASR + LLM backend toggles (the enums + wiring
  work; no visible toggle yet).
- B2 model-download / AirDrop UI for Parakeet weights.
- Refactoring the four LLM generators (radio / narrative / ZMIST /
  cleaner) to consume `TCCCLLMBackend` instead of talking to
  `TCCCLanguageModel` directly. The bridge exists; the rewire
  doesn't.
- Actually bundling LFM2 / Qwen weights — RESEARCH_LLM_SMALL.md
  recommends LFM2.5-1.2B-Instruct first.
