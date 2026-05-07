# DevTools Kokoro Splash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:dispatching-parallel-agents to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a launch splash with TCCC.ai and DevTools roles, plus a DevTools sender flow for Kokoro-only scenario playback scaffolding.

**Architecture:** Keep the existing casualty-management shell intact behind a root route selected from `SplashView`. DevTools owns a small sender/receiver navigation surface; sender state lives in `SenderViewModel`, ambient capture lives in `AmbientMeter`, playback visualization reads real audio levels only, and `KokoroEngine` is the sole TTS boundary.

**Tech Stack:** SwiftUI, Observation, AVFoundation, existing TCCC palette/type/layout tokens, local Kokoro-82M assets at `/Users/ama/Kokoro-82M`.

---

### Task 1: Splash And DevTools Landing

**Files:**
- Create: `TCCC_IOS/Splash/SplashView.swift`
- Create: `TCCC_IOS/DevTools/DevToolsLandingView.swift`
- Create: `TCCC_IOS/DevTools/Receiver/ReceiverPlaceholderView.swift`
- Modify: `TCCC_IOS/ContentView.swift`
- Create: `docs/devtools/self-review-agent-a.md`

- [ ] **Step 1: Add root route state local to ContentView**

Use a local enum in `ContentView.swift`:

```swift
private enum RootRoute {
    case splash
    case main
    case devTools
}
```

Render `SplashView` first, route `TCCC.ai` to the existing main app stack, and route `DevTools` to `DevToolsLandingView`.

- [ ] **Step 2: Build SplashView**

Use `palette`, `Layout`, `Panel`, and `BigButton` style choices already in the app. The two role buttons fill a landscape two-column layout and have at least `Layout.bigButtonHeight`.

- [ ] **Step 3: Build DevToolsLandingView and receiver placeholder**

Sender opens the sender flow once Task 4 exists. Receiver renders exactly `Receiver mode - coming soon` with the existing visual language and no networking imports.

- [ ] **Step 4: Verify**

Run:

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=F9D1EDB3-0711-4935-8A78-F720F85F09DE -configuration Debug -derivedDataPath /private/tmp/tccc_ios_devtools_agent_a build CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

Expected: `** BUILD SUCCEEDED **`.

### Task 2: Kokoro Engine Boundary

**Files:**
- Create: `TCCC_IOS/DevTools/TTS/KokoroEngine.swift`
- Create: `docs/devtools/kokoro-runtime-notes.md`
- Create: `docs/devtools/self-review-agent-b.md`

- [ ] **Step 1: Inspect Kokoro assets**

Confirm these local files exist:

```bash
ls -lh /Users/ama/Kokoro-82M/kokoro-v1_0.pth
find /Users/ama/Kokoro-82M/voices -maxdepth 1 -type f -name '*.pt'
```

Expected: `kokoro-v1_0.pth` is present and `af_heart.pt` is among the voicepacks.

- [ ] **Step 2: Add KokoroEngine API**

Implement these app-facing types:

```swift
struct KokoroVoice: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

enum KokoroEngineError: LocalizedError {
    case nativeRuntimeUnavailable(String)
    case emptyScript
}

struct KokoroSynthesisRequest: Sendable {
    let text: String
    let voiceID: String
    let speed: Double
    let pitchSemitones: Double
}

struct KokoroSynthesisResult: Sendable {
    let audioURL: URL
    let duration: TimeInterval
    let sentenceTimings: [KokoroSentenceTiming]
}
```

`synthesize` must throw `.nativeRuntimeUnavailable` until the user confirms a CoreML or MLX-Swift conversion path. Do not use Apple speech or fake audio.

- [ ] **Step 3: Document runtime blocker**

Write `docs/devtools/kokoro-runtime-notes.md` with the asset state and the reason no conversion was attempted: the cloned repo is PyTorch/LFS assets only, and the spec requires confirmation before conversion.

- [ ] **Step 4: Verify**

Run the same iPhone 15 Pro simulator build as Task 1 with `/private/tmp/tccc_ios_devtools_agent_b`.

### Task 3: Sender Compose And Ambient Meter

**Files:**
- Create: `TCCC_IOS/DevTools/Sender/SenderViewModel.swift`
- Create: `TCCC_IOS/DevTools/Sender/SenderComposeView.swift`
- Create: `TCCC_IOS/DevTools/Audio/AmbientMeter.swift`
- Create or append: `docs/devtools/sim-coverage-gaps.md`
- Create: `docs/devtools/self-review-agent-c.md`

- [ ] **Step 1: Add SenderViewModel state**

Use `@Observable` and keep these defaults: `readingWordsPerMinute = 150`, voice `af_heart`, speed `1.0`, pitch `0`, volume `0.8`.

- [ ] **Step 2: Add word count and reading time**

Count non-empty whitespace-separated tokens and compute:

```swift
let minutes = Double(max(wordCount, 1)) / Double(Self.readingWordsPerMinute)
```

Render `<1 min` below one minute and whole-minute values above that.

- [ ] **Step 3: Add AmbientMeter**

Use `AVAudioSession` category `.playAndRecord` or `.record` with mode `.measurement`, install an input tap, compute RMS dBFS, smooth at about 10 Hz, and stop on navigation away from compose.

- [ ] **Step 4: Build SenderComposeView**

Use a `TextEditor`, stats row, ambient panel, voice picker, speed/pitch/volume sliders, and a large Send/Play button. Send/Play stops ambient and asks the view model to synthesize through `KokoroEngine`.

- [ ] **Step 5: Verify**

Run the iPhone 15 Pro simulator build with `/private/tmp/tccc_ios_devtools_agent_c`.

### Task 4: Sender Readout And Playback Visualizer

**Files:**
- Create: `TCCC_IOS/DevTools/Sender/SenderReadoutView.swift`
- Create: `TCCC_IOS/DevTools/Audio/PlaybackVisualizer.swift`
- Create or append: `docs/devtools/sim-coverage-gaps.md`
- Create: `docs/devtools/self-review-agent-d.md`

- [ ] **Step 1: Add sentence-level highlighting**

Split the script into sentence ranges. Highlight the sentence matching the current playback time when sentence timings exist. If synthesis is unavailable, show the preserved script without a moving highlight.

- [ ] **Step 2: Add real-level visualizer**

Render bars from real playback level samples supplied by the view model. Zero samples render an inactive flat state. Do not generate decorative sine waves.

- [ ] **Step 3: Add transport controls**

Play/pause, stop, scrubber, current time, total time, mid-playback volume, and Re-edit. Controls must keep minimum 44 pt hit targets.

- [ ] **Step 4: Verify**

Run the iPhone 15 Pro simulator build with `/private/tmp/tccc_ios_devtools_agent_d`.

### Task 5: Orchestrator Integration

**Files:**
- Modify: integration seams touched by Tasks 1-4
- Create: `docs/devtools/orchestrator-self-review.md`

- [ ] **Step 1: Merge worker changes**

Resolve overlaps only in `ContentView.swift`, `SenderViewModel.swift`, and `docs/devtools/sim-coverage-gaps.md`.

- [ ] **Step 2: Build integrated app**

Run:

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=F9D1EDB3-0711-4935-8A78-F720F85F09DE -configuration Debug -derivedDataPath /private/tmp/tccc_ios_devtools_integrated build CODE_SIGNING_ALLOWED=NO -skipMacroValidation
```

- [ ] **Step 3: Smoke walk in simulator**

Launch the built app on the iPhone 15 Pro simulator and walk: splash, TCCC.ai, back by relaunch, DevTools, Sender, paste text, Send/Play, Readout, Re-edit, Receiver.

- [ ] **Step 4: Self-review and fix**

Write `docs/devtools/orchestrator-self-review.md`, address concrete issues, rebuild, and re-walk.

- [ ] **Step 5: Commit only after branch confirmation**

Commit/push only after the user confirms `origin/main@01662bc` is canonical.
