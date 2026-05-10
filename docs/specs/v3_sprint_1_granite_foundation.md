# TCCC_IOS — Granite Speech Foundation Sprint Spec (v3, Sprint 1)

**Sprint owner:** Mike (LCDR, NMCB-4 Battalion Surgeon)
**Repo root:** `/Users/ama/TCCC_IOS` (private GitHub)
**Target device:** physical iPhone 17 Pro (iOS 26)
**Working branch:** `main` (single trunk; no feature branches; no Lane B)
**Sprint scope:** Granite Speech transcribes on physical iPhone with sane memory. **Hot-seat integration is Sprint 2.**

**v3 changelog** (vs `SPRINT_TCCC_AUDIO_LLM_V2.md`):
- **Repo-aware, post-recon.** v2 assumed greenfield. The actual repo (per the agent's `RECON_NOTES.md`) already has `TranscriptStream`, `GraniteSpeechTranscriptStream` placeholder, `GraniteCandidatePatch`, hot-seat packet builder, `GraniteSchemaValidator`, `GraniteReviewQueue`, `MLXBackend.generateStructured(...)` wired through `Generable.Type`, `HFHubCache.contains(modelId:)` enforcing the no-RECORD-download policy, audio capture + `gainProvider` + `AudioLevels` patterns in `SpeechRecognizer` / `ParakeetTranscriptStream`. v3 patches into existing seams.
- **Sprint scope split.** v2 was G0–G6 in one document. v3 is **Sprint 1 only** — transcription works on device. Hot-seat integration becomes Sprint 2 (separate document, written when Sprint 1 lands).
- **`Packages/TCCCAudio/` is the new code home,** not `TCCC_IOS/Audio_LLM/` (would violate AGENTS.md "no logic in app target") and not `Packages/TCCCKit/` (would pull MLX into pure-logic modules). Mirrors the existing `Packages/TCCCLLM` shim pattern.
- **Storage decision: multi-source resolver, Files.app open-in-place primary.** Model files live in user-managed iCloud Drive or "On My iPhone" storage, accessed via `UIDocumentPickerViewController` + persistent security-scoped bookmark. Bundle resource and `MLXBackend.prefetch()` HF-cache stay as fallback resolution paths. Survives app reinstalls — bundling does not.
- **Stale-bookmark UX = banner with re-select tap target,** not auto-firing the picker. Matches the existing `MLXBackend` HF-cache-miss pattern.
- **Lane B / Canary parked entirely.** Single trunk. Canary becomes a future C-phase sprint when Granite is shipped, as a separate document.
- **iPad upscale deferred** to its own end-of-night addendum.
- **Token budget removed.** Opus 4.7 has 1M context; 200K-per-phase was anchored to a window size that no longer applies.
- **mlx-audio-swift pin = commit SHA** of the v0.1.2 tag, not a branch. Resolve via `git ls-remote https://github.com/Blaizzy/mlx-audio-swift refs/tags/v0.1.2`. Branch pinning is fragile.
- **DevTools-screen scope only.** Sprint 1 lives under DevTools landing as a "Granite Live" tile. Main 5-screen pager untouched. Cutover is Sprint 2.

---

## 1. Objective (Sprint 1)

Replace the `GraniteSpeechTranscriptStream` placeholder with a real `mlx-audio-swift`-backed `TranscriptStream` implementation that produces TCCC-keyword-biased transcripts on physical iPhone 17 Pro, accessed via a DevTools "Granite Live" view, while:
- Preserving Apple Speech as the runtime default ASR backend.
- Preserving Parakeet/FluidAudio as the existing alternate.
- Honoring AGENTS.md guardrails: no logic in app target, no hidden downloads from RECORD, no direct model-to-patient-state mutation, no transcript-as-instruction.

**Out of scope for Sprint 1** (parked for Sprint 2):
- Hot-seat integration: feeding Granite transcripts into `TranscriptSegmentLedger` → `HotSeatPacketBuilder` → `GranitePromptBuilder` → `GraniteCandidatePatch` → `GraniteSchemaValidator` → `GraniteReviewQueue`.
- Cutover from DevTools view into the main 5-screen pager.
- Switching `GraniteTextLLMBackend.modelId` from base to instruct-4bit (Sprint 2's text-LLM concern, not Sprint 1's ASR concern).

**Out of scope entirely** (parked or future sprints):
- Single-pass audio→JSON.
- Canary-Qwen integration (future C-phase sprint).
- Granite Speech 4.1 / Plus / NAR (no MLX artifact yet).
- iPad layout work (separate addendum).
- macOS / Mac Catalyst.
- Word-level timestamps (sentence-level via §8 is sufficient).
- Multi-casualty MASCAL handling.

---

## 2. Locked Decisions (Do Not Re-Litigate)

| Decision | Value |
|---|---|
| Architecture | Two-pass eventually (ASR → transcript → text-LLM); Sprint 1 ships only the ASR side via DevTools. Hot-seat wiring is Sprint 2. |
| Speech runtime | `Blaizzy/mlx-audio-swift` (MIT), pinned to commit SHA of the v0.1.2 tag |
| Speech model (primary, Sprint 1) | `mlx-community/granite-4.0-1b-speech-5bit` (~2.22 GB) — the only variant the Swift module's per-model README documents as supported |
| Speech model (deferred to future bake-off) | mxfp4 (1.93 GB), 4bit (1.99 GB), 8bit (2.9 GB). Test only after 5-bit ships and the Swift loader's quantization handling is verified |
| ASR default | Apple Speech (`SFSpeechRecognizer`) — unchanged |
| ASR alternates already wired | FluidAudio/Parakeet — unchanged |
| Granite Speech UI surface (Sprint 1) | DevTools landing tile → "Granite Live" view. Main 5-screen pager untouched. |
| Code location | New local package `Packages/TCCCAudio/` (mirrors `Packages/TCCCLLM` shim pattern). MLX-heavy deps live here, not in `Packages/TCCCKit` (pure logic) and not in the app target (AGENTS.md). |
| App target file changes | Only the `GraniteSpeechTranscriptStream.swift` placeholder body, the new DevTools tile, the new Settings row, and `Info.plist`/entitlements/`project.yml`. No app-target logic beyond what's already there. |
| Project generation | XcodeGen via `project.yml`. **Never hand-edit `.xcodeproj`.** |
| Model storage | **Multi-source resolver** (priority order): (1) user-selected Files.app folder via `UIDocumentPickerViewController` in `.open` mode, persistent security-scoped bookmark stored under `tccc.graniteSpeech.modelBookmarkV1`; (2) bundle resource path (for future MDM-deployed builds); (3) HF cache populated by explicit `MLXBackend.prefetch()` (matches existing text-LLM pattern). First match wins. Throws if none resolve. |
| Stale-bookmark UX | Banner with "Re-select model folder" tap target. Do not auto-fire the picker. Matches existing `HFHubCache.contains(modelId:)` miss UX. |
| Loader API contract | Resolver yields a URL the engine consumes. Engine adapts to whatever `MLXAudioSTT.GraniteSpeechModel.fromPretrained(...)` actually accepts (HF model ID vs. local URL). If the API only accepts an HF ID, the resolver seeds the HF cache directory from the picker URL before calling `fromPretrained`. Exact binding decided when source is read. |
| Audio framework | `AVFoundation` — already in use via `SpeechRecognizer` / `ParakeetTranscriptStream`. Reuse, don't reinvent. |
| Sample rate | 16 kHz mono Float32 (Granite Speech encoder contract) |
| Memory entitlements | `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing` (stripped on App Store distribution; works for Apple Developer / Enterprise / MDM — see §7) |
| Validation device | Physical iPhone 17 Pro. Simulator is blocked by MLX/Metal per the existing sprint board. |
| Self-verification | iPhone 17 Pro simulator (iOS 26) for everything that doesn't need real model execution. See §11. |

---

## 3. Repo Recon (Confirmed)

The agent ran `RECON_NOTES.md` at the repo root. Key facts the spec relies on:

- `Packages/TCCCKit/` — pure-logic package; contains `TranscriptStream` protocol, `GraniteCandidatePatch`, `GraniteSchemaValidator`, `GraniteReviewQueue`, `HFHubCache`. No MLX deps. New code does not go here.
- `Packages/TCCCLLM/` — LLM shim package; uses `AnyLanguageModel` 0.8.0 + `mlx-swift-lm` 2.25.5. Contains `MLXBackend` with `generateStructured(...generating: Generable.Type)` and `prefetch()`. Sprint 1's resolver-conflict mitigation (see §G0) avoids touching this package.
- `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` — 36-line placeholder actor; `authorize()`, `prime()`, `start()` all throw `backendUnavailable`. **This is the file Sprint 1 replaces the body of.**
- `TCCC_IOS/Audio/SpeechRecognizer.swift` and `ParakeetTranscriptStream.swift` — existing ASR backends. Audio capture, `gainProvider`, `AudioLevels` pattern lives here. Reuse.
- `TCCC_IOS/Views/DevToolsLandingView.swift` — existing DevTools landing. New "Granite Live" tile is added here.
- `TCCC_IOS/AppState.swift` (or wherever) — contains `ASRBackend` enum with `.appleSpeech` (default), `.fluidAudioParakeet`, `.graniteSpeech` (research-only flag). Update the comment, not the case.
- `Info.plist` — `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `UIBackgroundModes: audio` already present. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` already set (per agent recon) — required for the multi-source resolver's Files.app open-in-place path.
- `project.yml` — XcodeGen config; iOS 26 deployment target; FluidAudio 0.14.4 already pinned; depends on local `TCCCKit` + `TCCCLLM` packages.

If anything in this list contradicts what the agent finds at execution time, halt and update `RECON_NOTES.md` before proceeding.

---

## 4. What NOT to Build

The repo already has each of these. **Do not duplicate them in `Packages/TCCCAudio` or anywhere else.**

| Tempting to build | Already exists as |
|---|---|
| Templates layer (NineLine / ZMIST / DD1380 structs, `TemplateStore`, `SlotFillerRules`) | `GraniteCandidatePatch` + `GraniteSchemaValidator` + `GraniteReviewQueue` (in `Packages/TCCCKit`). **Sprint 2 work** wires Granite ASR into these — Sprint 1 does not touch them. |
| Audio capture engine (`TCCCAudioManager`, ring buffer, gain meter, makeup gain) | Existing `SpeechRecognizer` and `ParakeetTranscriptStream` already implement `AVAudioEngine` capture, `gainProvider`, `AudioLevels`. The new `GraniteSpeechRuntime` reuses these patterns or borrows the same plumbing — does not reinvent. |
| Recording UI (`TCCCRecordingView`) | `LiveCaptureScreen` is the production recording surface, already wired through Apple Speech and Parakeet. Sprint 1 does not modify it. New ASR work surfaces in DevTools only. |
| Constrained JSON generation library | `MLXBackend.generateStructured(input:generating: Generable.Type)` is already plumbed through `mlx-swift-structured`. Sprint 2 will use this for transcript→candidate-patch generation; Sprint 1 does not touch it. |
| HF cache gating, no-RECORD-download enforcement | `HFHubCache.contains(modelId:)` already enforces it. Granite Speech's resolver fallback path (3) calls into this same surface. |
| Granite text LLM swap (`base-4bit` → `4bit` instruct) | Sprint 2 work. Sprint 1 ships ASR only; the text LLM doesn't enter the picture until hot-seat integration. |

If the agent finds itself writing any of the above, halt and reconcile against this table.

---

## 5. Phases

### Phase G0 — Dependency resolution and scaffolding
**Goal:** Resolve `mlx-audio-swift` v0.1.2 into the SwiftPM graph without breaking the existing `TCCCLLM` shim. Build cleanly. **Do not touch `GraniteSpeechTranscriptStream.swift` body in this phase.**

**The resolver risk:** `mlx-audio-swift` v0.1.2 requires `mlx-swift` ≥ 0.30.6 and `mlx-swift-lm` ≥ 3.31.3. The existing `TCCCLLM` package uses `AnyLanguageModel` 0.8.0 with `mlx-swift-lm` 2.25.5. Adding `mlx-audio-swift` will likely force the resolver to pick `mlx-swift-lm` 3.x.

**Tasks:**
1. Audit local working tree state. Run `git status`, `git fetch origin`, `git log --oneline main..origin/main`. If local is behind origin or has uncommitted changes, halt and ask the operator.
2. Resolve mlx-audio-swift commit SHA: `git ls-remote https://github.com/Blaizzy/mlx-audio-swift refs/tags/v0.1.2`. Pin the resulting SHA.
3. Create new local package `Packages/TCCCAudio/` mirroring the `Packages/TCCCLLM/` shim layout. `Package.swift` depends on `mlx-audio-swift` (the pinned SHA). Add empty/skeleton sources so the package builds.
4. Edit `project.yml`:
   - Add the package and its products. Match the FluidAudio entry's existing YAML style.
   - Add `Packages/TCCCAudio` as a local package dependency for the app target.
5. Add memory entitlements to whatever `.entitlements` file the app target uses:
   ```xml
   <key>com.apple.developer.kernel.increased-memory-limit</key>
   <true/>
   <key>com.apple.developer.kernel.extended-virtual-addressing</key>
   <true/>
   ```
6. Run the build:
   ```bash
   cd /Users/ama/TCCC_IOS
   xcodegen generate
   xcodebuild -project TCCC_IOS.xcodeproj \
     -scheme TCCC_IOS \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26' \
     -configuration Debug build \
     CODE_SIGNING_ALLOWED=NO \
     -skipMacroValidation
   cd Packages/TCCCKit && swift test
   cd ../TCCCLLM && swift test
   cd ../TCCCAudio && swift test
   ```
   `-skipMacroValidation` is required because `AnyLanguageModel` ships Swift macros that Xcode normally asks to trust interactively (per upstream README).
7. **If the resolver fails:** the agent picks one of three recovery paths and documents the choice in `Packages/TCCCAudio/CLAUDE.md`:
   - **Path A — Upgrade `AnyLanguageModel`:** find a version that has moved to `mlx-swift-lm` 3.x.
   - **Path B — Replace the `AnyLanguageModel` shim:** if `TCCCLLM`'s use of `AnyLanguageModel` is thin enough, swap directly for `mlx-swift-lm` 3.x.
   - **Path C — Isolate `MLXAudio` further:** add an Adapter inside `Packages/TCCCAudio` that re-exports a Swift-Sendable surface so nothing else in the project pulls `mlx-swift-lm` 3.x transitively.
   - If all three fail, halt and emit `BLOCKED:`.

**Verification (autonomous, no operator screenshots):**
- `xcodebuild build` succeeds for both Debug and Release.
- All three package test suites pass.
- `Package.resolved` is committed.
- `os_proc_available_memory()` logged at app launch on the simulator shows the entitlement took effect (value ≥ 6 GB on a clean iPhone 17 Pro simulator foreground).
- `RECON_NOTES.md` updated with the chosen resolver-recovery path.

**Commit:** `phase G0: add TCCCAudio package + mlx-audio-swift dep + memory entitlements`

---

### Phase G1 — Multi-source model resolver and bookmark store
**Goal:** Build the storage layer. Settings UI for picking a model folder, persistent security-scoped bookmark, three-source resolver. No actual ASR yet.

**Tasks:**
1. In `Packages/TCCCAudio/Sources/`, create:
   - `GraniteSpeechBookmarkStore.swift` — wraps persistent security-scoped bookmark in `UserDefaults` under key `tccc.graniteSpeech.modelBookmarkV1`. Methods: `save(url:)`, `resolve() throws -> (URL, isStale: Bool)`, `clear()`. On stale, attempt to re-create using the still-resolved URL before the scope handle drops.
   - `GraniteSpeechModelResolver.swift` — three-source chain. Method: `resolve() async throws -> URL`. Tries: (a) bundle resource path `Bundle.main.url(forResource: "granite-4.0-1b-speech-5bit", withExtension: nil)`; (b) bookmark store; (c) `HFHubCache.contains(modelId: "mlx-community/granite-4.0-1b-speech-5bit")` and yields the cache directory if present. Throws `modelNotProvided` if all three miss.
2. In `TCCC_IOS/Views/`, add the Settings row "Select Granite Speech Model Folder":
   - Tapping fires `UIDocumentPickerViewController` in `.open` mode for folders.
   - Selected URL is written to `GraniteSpeechBookmarkStore`.
   - Status text shows "Bookmark active" / "No model selected" / "Bookmark stale — tap to re-select" depending on resolver state.
3. Implement `GraniteSpeechRuntime` actor in `Packages/TCCCAudio/Sources/`:
   - On `prime()`: calls resolver, opens security-scoped access on the resolved URL, holds the URL for the lifetime of the loaded model.
   - On `unload()` / `deinit`: calls `stopAccessingSecurityScopedResource`.
   - **Does not load any model yet** — that's G2's job. G1 just proves the resolver + lifecycle work.
4. Replace `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift` placeholder body:
   - `authorize()`: succeeds if `GraniteSpeechModelResolver.resolve()` succeeds; throws `backendUnavailable` otherwise.
   - `prime()`: wraps `GraniteSpeechRuntime.prime()`.
   - `start(audioURL:)`: throw "not yet implemented in G1" — G2 fills this in.
   - Update the `ASRBackend.graniteSpeech` comment from "research-only until Swift runtime exists" to "alternate ASR; requires configured local Granite Speech model folder".

**Test policy changes (this phase):**
The existing `GraniteSpeechTranscriptStream` tests assert "Swift runtime does not exist." Those assertions are now false history. Replace with **policy tests**:

```swift
// Policy: Granite Speech is selectable but not default.
func testGraniteSpeechIsExplicitAlternateASRBackend() {
    XCTAssertEqual(AppState.defaultASRBackend, .appleSpeech)
    XCTAssertTrue(AppState.availableASRBackends.contains(.graniteSpeech))
    XCTAssertNotEqual(AppState.availableASRBackends.first, .graniteSpeech)
}

// Policy: never download from RECORD path.
func testGraniteSpeechResolverThrowsWithoutAnySource() async throws {
    // No bundle resource, no bookmark, no HF cache.
    let resolver = GraniteSpeechModelResolver()
    await assertThrows { try await resolver.resolve() }
    // Verify zero network calls in the test mock.
    XCTAssertEqual(MockNetworkLayer.calls.count, 0)
}

// Policy: bookmark roundtrip works.
func testBookmarkSaveResolveStaleClearLifecycle() async throws {
    // Use a fixture directory in the test bundle as the "selected model folder".
    let store = GraniteSpeechBookmarkStore()
    let fixture = Bundle.module.url(forResource: "fake-model-fixture", withExtension: nil)!
    try store.save(url: fixture)
    let (resolved, isStale) = try store.resolve()
    XCTAssertEqual(resolved.lastPathComponent, fixture.lastPathComponent)
    XCTAssertFalse(isStale)
    store.clear()
    await assertThrows { try store.resolve() }
}

// Policy: real model load deferred to physical device.
@available(iOS 26, *)
func testGraniteSpeechPrimeWithConfiguredFolderOnSimulator() async throws {
    guard let modelDir = ProcessInfo.processInfo.environment["GRANITE_SPEECH_MODEL_DIR"] else {
        throw XCTSkip("Set GRANITE_SPEECH_MODEL_DIR to run")
    }
    // G1: prime() should succeed (resolver works); load is G2's problem.
    let stream = GraniteSpeechTranscriptStream(modelPath: modelDir)
    try await stream.authorize()
    try await stream.prime()
}
```

**Verification (autonomous):**
- All four policy tests pass on iPhone 17 Pro simulator.
- `xcodebuild build` succeeds with the new actor wired.
- Apple Speech remains the default (regression check).
- Settings flow works in simulator: tap "Select Granite Speech Model Folder" → picker opens → select a fake fixture folder → status shows "Bookmark active". Verify via `xcrun simctl spawn booted log show --predicate 'category contains "TCCC"'`.

**Commit:** `phase G1: granite speech multi-source resolver + bookmark store + policy tests`

---

### Phase G2 — Real model load on physical iPhone
**Goal:** `GraniteSpeechRuntime.prime()` actually loads `MLXAudioSTT.GraniteSpeechModel` from the resolved URL. `start(audioURL:)` produces a transcript. Validated on physical iPhone 17 Pro.

**Tasks:**
1. Read the upstream Granite Speech source folder to verify the loader API:
   ```bash
   git clone --depth 1 https://github.com/Blaizzy/mlx-audio-swift /tmp/mlxa-check
   cd /tmp/mlxa-check && git checkout <pinned-SHA>
   find Sources/MLXAudioSTT/Models/GraniteSpeech -type f
   cat Sources/MLXAudioSTT/Models/GraniteSpeech/README.md
   grep -R "fromPretrained\|modelPath\|Bundle\|hub\|cache" -n Sources/MLXAudioSTT/Models/GraniteSpeech
   ```
   Document the exact `GraniteSpeechModel` initializer surface in `Packages/TCCCAudio/CLAUDE.md`. If `fromPretrained(...)` only accepts an HF model ID:
   - The resolver's job extends: it must seed the HF cache at the expected location from the picker-resolved URL before `fromPretrained` is called. The HuggingFaceHub Swift library lets you set the cache directory; use it.
2. Wire the loader into `GraniteSpeechRuntime.prime()`. Cache the loaded model in actor state. Log `phys_footprint` delta around the load via `MemoryMonitor` (see §7).
3. Implement `GraniteSpeechRuntime.transcribe(audioURL:) -> AsyncStream<TranscriptSegment>`:
   - Build the keyword-biasing prompt (§ below).
   - Call `MLXAudioSTT.GraniteSpeechModel.generateStream(...)` (or whatever the verified API is).
   - Yield transcript segments through the stream.
4. Wire `GraniteSpeechTranscriptStream.start(audioURL:)` to feed the runtime stream into the `TranscriptStream` protocol's expected output mechanism.
5. Add the keyword-biasing prompt as a constant in `Packages/TCCCAudio/Sources/.../GraniteSpeechPrompt.swift`:
   ```swift
   public enum GraniteSpeechPrompt {
       public static let asr = """
       <|audio|>can you transcribe the speech into a written format?
       Keywords: tourniquet, TXA, GSW, ZMIST, DD1380, AVPU, SpO2, MEDEVAC, 9-line, \
       MARCH, hemorrhage, pneumothorax, ketamine, fentanyl, morphine, moxifloxacin, \
       ertapenem, cefazolin, Hextend, lactated ringer's, whole blood, plasma, \
       needle decompression, chest seal, NPA, cric, Reaper, Dawson, NKDA.
       """
   }
   ```

**Verification (operator participation required for the device portion):**
- Stage `mlx-community/granite-4.0-1b-speech-5bit` into iCloud Drive or "On My iPhone" via AirDrop/USB.
- Bundle the 5-min test fixture as `test_5min.wav` (16 kHz mono) in `Packages/TCCCAudio/Tests/Fixtures/`. Generate via `say` + `afconvert` from the narrative text in v1's §6.
- Run a debug-only "Bake-off" mode in DevTools that:
  - Loads the model. Records load time and `phys_footprint` delta.
  - Transcribes the bundled fixture. Records total transcription time and peak `phys_footprint`.
  - Writes a row to `BAKEOFF_RESULTS.md`.
- Assert keyword recall ≥ 90% on the §6 token list.
- Assert peak `phys_footprint` stays under §7's runtime cap throughout the 5-minute fixture.

**Commit:** `phase G2: granite speech model load + transcribe on physical iPhone`

---

### Phase G3 — DevTools "Granite Live" view
**Goal:** Live ASR via Granite Speech, surfaced in a new DevTools tile. Main 5-screen pager untouched.

**Tasks:**
1. Add `TCCC_IOS/Views/DevTools/GraniteLiveView.swift`:
   - Record button (red/grey toggled).
   - Live transcript text area (append-only as segments arrive).
   - Three memory gauges side-by-side (per §7): Resident, **Footprint** (bold), Available. Color shifts at runtime-computed warning/critical thresholds.
   - Memory pressure event banner (per §7).
   - "Resolver status" line showing which source the model loaded from (bundle / bookmark / HF cache).
2. Add a "Granite Live" tile to `DevToolsLandingView`. Match the existing tile style.
3. Wire the view to `GraniteSpeechTranscriptStream` via the existing `TranscriptStream` protocol path.
4. Audio engine plumbing: reuse the `SpeechRecognizer` / `ParakeetTranscriptStream` capture pattern. Do not write a new capture engine.

**Verification:**
- `xcodebuild build` for Debug and Release succeeds.
- Snapshot test renders `GraniteLiveView` in three states (idle, recording-active, error) against bundled reference PNGs.
- On physical iPhone with the bookmark configured: tap Granite Live tile → grant mic → tap record → speak the §6 fixture content → transcript populates → memory gauges live-update. No crashes, no jetsam.

**Commit:** `phase G3: granite live devtools view + memory gauges`

---

### Phase G4 — Sprint 1 acceptance gate
**Goal:** Walk §13 acceptance as a single pass/fail check on physical iPhone 17 Pro.

**Tasks:**
1. Walk the §13 checklist. Generate `SPRINT_1_ACCEPTANCE.md` with each criterion marked pass/fail/partial with evidence (timestamps, log excerpts, screenshots).
2. Tag the commit `sprint-1-granite-speech-foundation`.

**Commit:** `phase G4: sprint 1 acceptance gate signed off`

---

## 6. Bundled Test Fixture

The 5-minute narrative fixture is unchanged from v1; see `SPRINT_TCCC_AUDIO_LLM.md` §6 for the full text. Acceptance baseline tokens that MUST be heard (keyword recall ≥ 90%):

```
8734, 9120, 44.50, Reaper, urgent surgical, GSW, chest,
AVPU P, pain, SpO2, 88, 93, TXA, Hextend, chest seal,
needle decompression, NKDA, Dawson, RD6942, 6942
```

---

## 7. Memory Pressure Monitoring

The 3.5 GB cap from v1 was wrong. The right ceiling is **runtime-computed**: `cap = phys_footprint + os_proc_available_memory()` measured at app launch; warning at 75% × cap; critical at 90% × cap.

**Where this lives in the repo:** `Packages/TCCCAudio/Sources/.../MemoryMonitor.swift`. (Could equally live in `TCCCKit` since it's pure logic, but Sprint 1 keeps it co-located with the actor that primarily uses it. Move to `TCCCKit` in Sprint 2 if hot-seat needs it too.)

**The right metric is `phys_footprint` from `task_vm_info`,** not `resident_size`. Jetsam fires on `phys_footprint`. Three published metrics: `residentMB`, `physFootprintMB`, `availableMB`, plus `pressure: .normal | .warning | .critical`.

```swift
import Darwin
import os.log

final class MemoryMonitor: ObservableObject {
    @Published var residentMB: Double = 0
    @Published var physFootprintMB: Double = 0
    @Published var availableMB: Double = 0
    @Published var pressure: MemoryPressure = .normal

    enum MemoryPressure { case normal, warning, critical }

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

    static func availableBytes() -> UInt64 { os_proc_available_memory() }

    // Subscribe to system pressure events:
    // DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
}
```

**Pressure response policy (Sprint 1):**
- `.normal` → no action.
- `.warning` → OSSignpost; UI gauge amber.
- `.critical` → OSSignpost + UI banner; pause new ASR generation for one cycle; resume on subsidence; UI gauge red.
- Subscribe to `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` for system-level events.

**Logging:** `MemoryMonitorLog.csv` to the app's Documents directory. Timestamp, resident_mb, footprint_mb, available_mb, pressure_level, event. Jetsam forensics file when something dies.

**Entitlement caveat:** `com.apple.developer.kernel.increased-memory-limit` is stripped on App Store distribution builds. Verify at runtime by logging `os_proc_available_memory()` early in app launch.

---

## 8. Sentence-Level Timestamps

Granite Speech 4.0 1B does not emit explicit timestamps. Derive them from:
- The audio side: each input chunk carries a host-time range from the audio engine.
- The transcript side: punctuation in Granite's output marks sentence boundaries.
- Each transcript segment in the eventual ledger inherits its source chunk's time range.

This delivers "sentence-level is sufficient" without requiring word-level timestamps from the model. Word-level needs Granite Speech 4.1 Plus, which is parked.

---

## 9. Known Issues & Stale Documentation

1. **mlx-audio-swift's top-level README is stale.** The STT model table omits Granite Speech, but PR #95 ("Add granite speech 4") landed in v0.1.2 (Mar 14, 2026). Truth lives in `Sources/MLXAudioSTT/Models/GraniteSpeech/README.md` and the source folder. Verified via `find` and `grep` in the agent's recon.
2. **The `increased-memory-limit` entitlement is stripped on App Store distribution.** Verify at runtime via `os_proc_available_memory()` early in app launch (Apple Developer Forums #770868). For DoD/enterprise/MDM distribution, it works.
3. **`fromPretrained` API uncertainty.** May accept HF model ID only, or also a local URL. G2 task 1 verifies by reading the source. The resolver design is flexible enough to seed an HF cache from a Files.app picker URL if the API only accepts model IDs.
4. **MLX/Metal blocked on simulator.** Real model execution requires physical iPhone 17 Pro. Tests that depend on real model loading must be gated with `#if !targetEnvironment(simulator)` or env-var skips.
5. **`mlx-swift-structured` is at v0.1.0 (Apr 6, 2026)** — already integrated via existing `MLXBackend.generateStructured(...)`. Sprint 1 doesn't touch it; Sprint 2 will.
6. **The repo's prior Granite Speech tests assert unavailability** — those are false history. Delete or rewrite per §G1.
7. **Working tree hygiene.** Local may be behind `origin/main` with stale uncommitted deletions. G0 task 1 audits this and halts if needed.

---

## 10. Fallback Paths

| If… | Then… |
|---|---|
| G0 SwiftPM resolver fails (mlx-swift-lm 2.x vs 3.x conflict) | Try Path A (upgrade `AnyLanguageModel`), then Path B (replace shim), then Path C (Adapter inside `TCCCAudio` re-exporting Sendable surface). All three documented in G0 task 7. Halt with `BLOCKED:` only after all three attempted. |
| `MLXAudioSTT.GraniteSpeechModel.fromPretrained(...)` only accepts HF model IDs | Resolver seeds the HF cache directory from the picker-resolved URL via `FileManager.copyItem` before calling `fromPretrained`. The HuggingFaceHub Swift library exposes the cache directory; use it. Alternatively, submit a one-day PR to mlx-audio-swift adding a `modelPath:` overload (Blaizzy is responsive). |
| 5-bit speech model fails keyword recall ≥ 90% on the fixture | Run 8-bit (accuracy benchmark) to confirm the model is the bottleneck and not the prompt or audio pipeline. If 8-bit also fails, the issue is upstream — check resampling, gain, or prompt format. If 8-bit passes and 5-bit fails, ship 8-bit despite the larger footprint as long as §7's cap allows. |
| Smaller variants (4-bit, mxfp4) don't load through the Swift loader | Stay on 5-bit. Smaller variants are a memory optimization, not a Sprint 1 requirement. |
| Physical iPhone hits jetsam during the 5-min fixture | Check the entitlement is active (`os_proc_available_memory()` log). If yes, drop to a smaller speech variant or restrict KV cache. |
| Granite Speech transcript quality is worse than Apple Speech default | Apple Speech remains default. Granite is alternate. There's no obligation to ship Granite as primary — its value is keyword biasing for TCCC vocabulary. If recall doesn't beat Apple Speech, Sprint 1 still ships (Granite as explicit alternate operator can switch to). |
| `xcodebuild test` flakes in CI but passes locally | `XCTSkip` on CI; do not delete. Document in `Packages/TCCCAudio/CLAUDE.md`. |

---

## 11. Self-Verification Discipline

The agent uses the iPhone 17 Pro simulator (iOS 26) for autonomous verification of everything that doesn't require real model execution. **Don't ask Mike to screenshot anything that the agent can verify itself.**

What the simulator handles:
- `xcodebuild build` for `iphonesimulator` destination.
- `xcodebuild test` and `swift test` for all package targets.
- All four policy tests in §G1 (resolver throws without source, default ASR is Apple Speech, bookmark roundtrip, prime-with-fixture).
- UI integration test of Settings → "Select Granite Speech Model Folder" → picker → bookmark roundtrip with a fake-model fixture directory.
- Audio engine plumbing with synthetic audio sources (no model needed; verify gain meter, resampler, ring buffer, `TranscriptStream` protocol contract surface).
- Snapshot tests of `GraniteLiveView`.

How to read your own output:
```bash
xcrun simctl spawn booted log show --predicate 'category contains "TCCC"' --last 5m
xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26' ... | tee /tmp/build.log
git diff   # before every commit
```

What requires the operator + physical iPhone:
- §G2 model load + transcribe (MLX/Metal does not run in simulator).
- §G3 device-side memory observations during 5-minute recording.
- §G4 Sprint 1 acceptance gate.

When those operator-required steps come up, the agent posts a clear, copyable prompt with the exact commands or actions needed and then waits.

**Subagent parallelism** is handled by Superpowers (`/subagent-driven-development`). Use it for read-heavy verification work — reading multiple repo files, verifying API surfaces of multiple SwiftPM packages, parallel `find`/`grep` across the codebase. Don't try to parallelize the SwiftPM resolver dance (sequential by nature) or the device bake-off (single physical iPhone).

---

## 12. Future Work (Parked, Not in This Sprint)

**Sprint 2 — Hot-seat integration.** Wire Granite ASR transcripts into the existing `TranscriptSegmentLedger` → `HotSeatPacketBuilder` → `GranitePromptBuilder` → `GraniteCandidatePatch` → `GraniteSchemaValidator` → `GraniteReviewQueue` pipeline. Switch `GraniteTextLLMBackend.modelId` from `granite-4.0-h-1b-base-4bit` to `granite-4.0-h-1b-4bit` (instruct, per the prior smoke-test record). Cut over from DevTools view into the main 5-screen pager. Sentence-level timestamp plumbing into the ledger. Separate spec document, written when Sprint 1 lands.

**Canary-Qwen integration.** Real implementation work — port FastConformer encoder + LoRA + projection into `Packages/TCCCAudio` using the existing `Qwen2.5-2.5B-Instruct` MLX port. Adds a new `.canaryQwen` case to `ASRBackend`. Same single-trunk model. License is CC-BY-4.0; permissive for this use.

**Granite Speech 4.1 2B upgrade.** Better WER (5.33 vs 5.52). No mlx-community port exists yet. When one appears, swap the speech model ID. Future sprint.

**Granite Speech 4.1 Plus.** Speaker attribution + word-level timestamps. Requires the Plus variant to be MLX-converted and Swift-loaded. Sentence-level via §8 is sufficient for v1.0.

**Speech model bake-off.** Test 4-bit and mxfp4 against 5-bit baseline once the Swift loader's quantization handling is verified. Decide on smallest viable variant for production deployment.

**iPad upscale.** Add iPad as a destination in `project.yml`. Verify the existing `LiveCaptureScreen` and the new `GraniteLiveView` layouts don't break on the wider canvas. Address layout breakage as a separate sprint. Architecture is iPad-agnostic; layout work is the entire scope.

**macOS / Mac Catalyst.** Out of scope.

---

## 13. Final Acceptance Criteria (Sprint 1)

On a clean iPhone 17 Pro device with the entitlements active:

1. App launches via existing sign-in. Apple Speech remains the default ASR (regression check).
2. Settings shows "Select Granite Speech Model Folder" row. Tapping opens `UIDocumentPickerViewController`.
3. Selecting a folder containing `mlx-community/granite-4.0-1b-speech-5bit` files writes a persistent security-scoped bookmark. Status text shows "Bookmark active".
4. With bookmark cleared and no HF cache populated, attempting to use Granite Speech surfaces a clear error message and falls back gracefully (does not start a hidden download).
5. With bookmark active, the DevTools "Granite Live" tile loads `GraniteLiveView`, mic permission prompt appears, recording transcribes via Granite Speech, the 5-min fixture transcribes with keyword recall ≥ 90% on the §6 token list.
6. Memory gauges visible during recording. `phys_footprint` stays under §7's runtime cap throughout the 5-minute fixture.
7. `MemoryMonitorLog.csv` is non-empty and shows OSSignpost intervals around model load and inference.
8. After app reinstall, the bookmark persists (because the model files live in user-managed Files.app storage, not the app sandbox). Tapping into Granite Live works without re-selecting the folder.
9. `git log --oneline | head -5` shows G0–G4 phase commits.

If any criterion fails, halt and emit `BLOCKED:`.

---

## 14. CLAUDE.md Merge Protocol

- **Root `CLAUDE.md`:** append-only. New section `## TCCC Granite Speech Foundation (Sprint 1)` with one-paragraph summary linking to `Packages/TCCCAudio/CLAUDE.md`.
- **`Packages/TCCCAudio/CLAUDE.md`:** per-phase journal. Each phase appends a dated section: locked decisions, API versions pinned, `phys_footprint` measurements, the chosen resolver-recovery path (if G0 needed one), any deviations from this spec.
- Never delete from `CLAUDE.md`. Supersede with `[SUPERSEDED YYYY-MM-DD: ...]`.

---

## 15. Commit Message Format

```
phase GN: <verb> <subject>

- bullet of what landed
- bullet of what was deferred
- bullet of any BLOCKED: items

Files changed: <count>
```

Single trunk on `main`. End every phase with `git push origin main`.

---

## 16. Download & Documentation Reference Card

| Component | Download / Source | License | Docs |
|---|---|---|---|
| `mlx-audio-swift` v0.1.2 | https://github.com/Blaizzy/mlx-audio-swift | MIT | Per-model READMEs in `Sources/MLXAudioSTT/Models/<Name>/README.md`. **Top-level README is stale** — do not trust its STT model table. Release notes: https://github.com/Blaizzy/mlx-audio-swift/releases/tag/v0.1.2. PR #95 added Granite Speech 4. |
| `mlx-swift` | https://github.com/ml-explore/mlx-swift | MIT | https://swiftpackageindex.com/ml-explore/mlx-swift |
| `mlx-swift-structured` v0.1.0 | https://github.com/petrukha-ivan/mlx-swift-structured | Apache 2.0 | Already integrated via existing `MLXBackend.generateStructured(...)`; Sprint 1 doesn't touch it. |
| Granite Speech 4.0 1B 5-bit (Sprint 1 primary) | https://huggingface.co/mlx-community/granite-4.0-1b-speech-5bit | Apache 2.0 | Upstream https://huggingface.co/ibm-granite/granite-4.0-1b-speech |
| Granite Speech 4.0 1B mxfp4 (deferred) | https://huggingface.co/mlx-community/granite-4.0-1b-speech-mxfp4 | Apache 2.0 | Same upstream |
| Granite Speech 4.0 1B 4bit (deferred) | https://huggingface.co/mlx-community/granite-4.0-1b-speech-4bit | Apache 2.0 | Same upstream |
| Granite Speech 4.0 1B 8bit (benchmark only) | https://huggingface.co/mlx-community/granite-4.0-1b-speech-8bit | Apache 2.0 | Same upstream |
| Apple `os_proc_available_memory` | iOS 13+ | Apple SDK | https://developer.apple.com/documentation/foundation/1490575-os_proc_available_memory |
| `task_vm_info` / `phys_footprint` | mach API | Apple SDK | Apple Developer Forums #770868 (entitlement stripping note) |
| Increased-memory-limit entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit | Apple SDK | Apple Developer Forums #685084, #770868 |
| Extended-virtual-addressing entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing | Apple SDK | Same |
| XcodeGen | https://github.com/yonaskolb/XcodeGen | MIT | `project.yml` reference: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md |

---

*End of v3 (Sprint 1) spec. Hand to one Claude Code instance in `/Users/ama/TCCC_IOS`. Single trunk. G0–G4 in order. Sprint 2 spec is written when Sprint 1 lands.*
