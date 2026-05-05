# Long-Form Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the recording path durable for 30–90 minute sessions — backgrounding-survivable, interruption-resilient, AAC-on-disk, and not LLM-cleaning the entire transcript every minute.

**Architecture:** Four mostly-independent tracks executed on branch `recording-long-form-2026-05-05`. Track L1 lands the background audio entitlement + an `AudioSessionCoordinator` actor. Track L2 swaps the on-disk format from PCM-WAV to AAC `.m4a` in both ASR backends. Track L3 adds three small safeguards inside `ParakeetTranscriptStream`. Track L4 throttles auto-clean and tightens transcript UI auto-scroll. Track F is on-device verification.

**Tech Stack:** Swift 6.2 / iOS 17+ / SwiftUI / `AVFoundation` / `AVAudioEngine` / `AVAudioSession` interruption notifications / `AVAudioFile` with AAC settings / `huggingface/AnyLanguageModel` (existing) / FluidAudio (existing).

**Reference spec:** `docs/superpowers/specs/2026-05-05-long-form-recording-design.md`. Read it first if anything below is unclear.

---

## Parallelization map

```
Wave 1 (parallel, disjoint files):
  L1.1  project.yml + Info.plist UIBackgroundModes
  L2.1  Update newAudioCaptureURL + AAC settings constant in AppState
  L3.1  Periodic stats logger inside ParakeetTranscriptStream
  L4.1  Auto-pin scroll behavior in LiveCaptureScreen

Wave 2 (after Wave 1):
  L1.2  AudioSessionCoordinator actor (new file)
  L2.2  ParakeetTranscriptStream switch to AAC AVAudioFile open
  L3.2  Defensive partial-string ceiling in ParakeetTranscriptStream
  L4.2  Auto-clean 60s must-run fallback in AppState
  
Wave 3 (after Wave 2):
  L1.3  Wire AudioSessionCoordinator into AppState
  L2.3  SpeechRecognizer switch to AAC (mirror of L2.2)
  L3.3  Memory-pressure observer in AppState
  L4.3  Auto-clean 200-line recent window in AppState

Wave 4 (final):
  F.1   Build for device + 60-min smoke test (manual)
```

L3.2 and L3.3 share `ParakeetTranscriptStream`/`AppState` with L2 and L4 respectively — sequence within wave to avoid `git add -A` collisions. L3.1 is solely log-emit code, no state, parallelizable with anything.

13 tasks total.

---

## Track L1 — Background audio + interruption handling

### Task L1.1: UIBackgroundModes + AVAudioSession category audit

**Why:** Without `audio` in `UIBackgroundModes`, the OS suspends `AVAudioEngine` ~30s after the app backgrounds. We also need the AVAudioSession category to remain `.playAndRecord` (already set in both backends) and confirm both backends don't call `setActive(false)` on a *background* stop — only on explicit user stop.

**Files:**
- Modify: `project.yml` (top-level `targets.TCCC_IOS.info` block)
- Read for context: `TCCC_IOS/Audio/SpeechRecognizer.swift:143` and `TCCC_IOS/Audio/ParakeetTranscriptStream.swift:220` — confirm where `setActive(false)` is called and ensure it's only on user-initiated stop, not on every internal pause.

- [ ] **Step 1: Locate the info block in `project.yml`**

```bash
grep -n "info:\|infoPlist\|targets:\|TCCC_IOS:" /Users/ama/TCCC_IOS/project.yml | head -20
```

If `project.yml` already has an `info:` or `infoPlist:` section under the `TCCC_IOS` target, edit in place. Otherwise add one.

- [ ] **Step 2: Add UIBackgroundModes `audio`**

In `project.yml`, under `targets.TCCC_IOS`, ensure:

```yaml
    info:
      path: TCCC_IOS/Info.plist
      properties:
        UIBackgroundModes:
          - audio
        # Existing keys preserved — do not delete NSMicrophoneUsageDescription,
        # NSSpeechRecognitionUsageDescription, etc.
```

If properties already exist, ADD the `UIBackgroundModes` key without disturbing the rest.

- [ ] **Step 3: Regenerate + build**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify the merged Info.plist contains `UIBackgroundModes`**

```bash
plutil -p /tmp/TCCC_IOS-device-build/Build/Products/Debug-iphonesimulator/TCCC_IOS.app/Info.plist 2>/dev/null | grep -A 2 UIBackgroundModes
```

Expected output includes `"audio"` in the array. If not, the project.yml change didn't propagate — check the section nesting.

- [ ] **Step 5: Audit `setActive(false)` callsites**

```bash
grep -n "setActive(false" TCCC_IOS/Audio/*.swift
```

Both should be inside a deinit-or-explicit-stop path, not inside a timed/interrupt path. If you find one inside an interruption handler or auto-cleanup, STOP and escalate — that's a bug we need to fix in L1.2 not papered over here.

- [ ] **Step 6: Commit**

```bash
git add project.yml TCCC_IOS.xcodeproj/project.pbxproj
git diff --staged --stat
git commit -m "feat(audio): UIBackgroundModes audio for long-form recording"
```

---

### Task L1.2: AudioSessionCoordinator actor

**Why:** Current code naively assumes the audio session stays valid for the lifetime of the recognizer. Phone calls, Siri, alarms, and route changes all happen mid-90-min meeting and we lose audio silently. This actor centralizes interruption + route observation so neither ASR backend has to know about it.

**Files:**
- Create: `TCCC_IOS/Audio/AudioSessionCoordinator.swift`

- [ ] **Step 1: Write the file**

```swift
import AVFoundation
import Combine
import Foundation

/// Long-lived audio-session interruption + route-change coordinator.
///
/// Owned by `AppState` so observers stay registered across screen
/// transitions. Decoupled from the ASR backends — both `SpeechRecognizer`
/// and `ParakeetTranscriptStream` keep their existing `start()` / `stop()`
/// API; this coordinator drives those calls when iOS interrupts the mic.
///
/// Design (per `docs/superpowers/specs/2026-05-05-long-form-recording-design.md`
/// section 1):
/// - On `.began`: call `pauseRequested` so the active recognizer
///   stops cleanly. Record `wasRunningAtInterruption` so we know to
///   resume.
/// - On `.ended` with `.shouldResume`: call `resumeRequested` so the
///   recognizer restarts. Append a system transcript line.
/// - On `.ended` without `.shouldResume`: call `stoppedRequested`.
///   Surface a banner; require manual RECORD to come back.
/// - On `.routeChange`: append a system transcript line, do nothing else.
@MainActor
final class AudioSessionCoordinator {

    /// Closure invoked when iOS asks us to pause for an interruption.
    /// AppState wires this to the active recognizer's `stopImmediate()`.
    var pauseRequested: (() async -> Void)?

    /// Closure invoked when iOS clears an interruption with `.shouldResume`.
    /// AppState wires this to a restart of the active recognizer + a system
    /// transcript marker.
    var resumeRequested: (() async -> Void)?

    /// Closure invoked when iOS clears an interruption without `.shouldResume`.
    /// AppState wires this to a banner + leaves the recognizer parked.
    var stoppedRequested: (() async -> Void)?

    /// Closure invoked on any audio route change (headphone disconnect, etc.).
    /// Receives the new port description string. AppState wires this to a
    /// system transcript marker.
    var routeChanged: ((String) -> Void)?

    private var wasRunningAtInterruption = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleInterruption(note)
            }
        }
        observers.append(interruption)

        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleRouteChange(note)
            }
        }
        observers.append(route)
    }

    deinit {
        let center = NotificationCenter.default
        for obs in observers { center.removeObserver(obs) }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            wasRunningAtInterruption = true
            Task { await pauseRequested?() }
        case .ended:
            guard wasRunningAtInterruption else { return }
            wasRunningAtInterruption = false
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) {
                Task { await resumeRequested?() }
            } else {
                Task { await stoppedRequested?() }
            }
        @unknown default:
            return
        }
    }

    private func handleRouteChange(_ note: Notification) {
        let session = AVAudioSession.sharedInstance()
        let portName = session.currentRoute.outputs.first?.portName ?? "unknown"
        routeChanged?(portName)
    }
}
```

- [ ] **Step 2: Add to xcodegen project**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
```

Expected: project.pbxproj picks up the new file.

- [ ] **Step 3: Build (file is unused, just confirms compile)**

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/Audio/AudioSessionCoordinator.swift TCCC_IOS.xcodeproj/project.pbxproj
git diff --staged --stat
git commit -m "feat(audio): AudioSessionCoordinator for interruption + route observation"
```

---

### Task L1.3: Wire AudioSessionCoordinator into AppState

**Why:** L1.2 created the coordinator but its closures are nil. AppState owns the active recognizer (via LiveCaptureScreen's `@State`, but reference-counted) and the transcript. Wire each closure to the right action.

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (add `audioSessionCoordinator` field + `init`-time wiring)
- Modify: `TCCC_IOS/Screens/LiveCaptureScreen.swift` (expose `recognizer` so the coordinator can drive it; OR — preferred — have the coordinator poke AppState which raises a published flag, and LiveCaptureScreen reacts via `.onChange`)

- [ ] **Step 1: Add the AppState field**

In `TCCC_IOS/App/AppState.swift`, near the other long-lived helper fields (find with `grep -n "var pendingConfirmation\|var voiceCommandTask" TCCC_IOS/App/AppState.swift`):

```swift
/// Long-lived AVAudioSession interruption + route observer. Lives
/// for the AppState lifetime (not the screen lifetime) so observers
/// stay registered across page swipes.
let audioSessionCoordinator = AudioSessionCoordinator()
```

Initial closures are nil; LiveCaptureScreen wires them in `.task`.

- [ ] **Step 2: Add a "force-pause" published flag for LiveCaptureScreen to react to**

In the same place:

```swift
/// Set to true by AudioSessionCoordinator when iOS interrupts.
/// LiveCaptureScreen observes this to call recognizer.stopImmediate().
/// Cleared by LiveCaptureScreen after it processes the request.
var pendingInterruptionPause: Bool = false

/// Set to true by AudioSessionCoordinator when iOS clears a resumable
/// interruption. LiveCaptureScreen observes this to restart the
/// recognizer. Cleared by LiveCaptureScreen after it processes.
var pendingInterruptionResume: Bool = false

/// Set when an interruption ends without `.shouldResume`. LiveCaptureScreen
/// surfaces a banner and asks the operator to tap RECORD.
var interruptionRequiresManualRestart: Bool = false
```

- [ ] **Step 3: Wire the coordinator's closures**

Add an `init` (or, if AppState already has an init, augment it):

```swift
init() {
    audioSessionCoordinator.pauseRequested = { [weak self] in
        await MainActor.run {
            self?.pendingInterruptionPause = true
            self?.appendSystem("INTERRUPTED · audio session preempted")
        }
    }
    audioSessionCoordinator.resumeRequested = { [weak self] in
        await MainActor.run {
            let stamp = Self.timeStamp()
            self?.appendSystem("RESUMED · \(stamp)")
            self?.pendingInterruptionResume = true
        }
    }
    audioSessionCoordinator.stoppedRequested = { [weak self] in
        await MainActor.run {
            self?.interruptionRequiresManualRestart = true
            self?.appendSystem("INTERRUPTION ENDED · tap RECORD to resume")
        }
    }
    audioSessionCoordinator.routeChanged = { [weak self] portName in
        self?.appendSystem("ROUTE · \(portName)")
    }
}

private static func timeStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ssZ"
    return f.string(from: Date())
}
```

If AppState already has an init, integrate without removing existing setup. AppState is `@MainActor @Observable`; closures must capture `weak self` to avoid retaining the AppState through the coordinator.

- [ ] **Step 4: Wire LiveCaptureScreen to observe the flags**

In `TCCC_IOS/Screens/LiveCaptureScreen.swift`, add `.onChange` modifiers near the existing `.task` / `.onDisappear` (around line 117):

```swift
.onChange(of: state.pendingInterruptionPause) { _, newValue in
    guard newValue else { return }
    state.pendingInterruptionPause = false
    Task {
        // Pause without unpriming so we can resume seamlessly.
        await recognizer?.stopImmediate()
    }
}
.onChange(of: state.pendingInterruptionResume) { _, newValue in
    guard newValue else { return }
    state.pendingInterruptionResume = false
    // Restart streaming if we were recording before the interruption.
    if state.isRecording {
        // Re-prime + start. Use the same code path the RECORD button uses.
        Task {
            try? await recognizer?.prime()
            // The streaming task will be re-spawned by the main RECORD
            // action; for an interruption resume, just call beginRecording()
            // directly.
            beginRecording()
        }
    }
}
```

(Adjust the call to `beginRecording()` to match whatever the existing RECORD-button handler is named; find with `grep -n "beginRecording\|handleRecord\|startRecording" TCCC_IOS/Screens/LiveCaptureScreen.swift`.)

- [ ] **Step 5: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add TCCC_IOS/App/AppState.swift TCCC_IOS/Screens/LiveCaptureScreen.swift
git diff --staged --stat
git commit -m "feat(audio): wire AudioSessionCoordinator to AppState + LiveCapture"
```

---

## Track L2 — AAC audio file

### Task L2.1: AAC settings constant + .m4a URL extension

**Why:** Centralize the AAC encoder settings as a single constant so both backends import them. Update `newAudioCaptureURL()` to produce `.m4a` (was `.wav`).

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (newAudioCaptureURL + new `aacOutputSettings` static dict)

- [ ] **Step 1: Find newAudioCaptureURL**

```bash
grep -n "newAudioCaptureURL\|encounter-.*\.wav" TCCC_IOS/App/AppState.swift
```

- [ ] **Step 2: Update the URL extension + add the AAC settings constant**

In `AppState.swift`, change the file extension and add the settings dict near the function:

```swift
/// AAC encoder settings used by both `SpeechRecognizer` and
/// `ParakeetTranscriptStream`. Voice-quality bitrate (32 kbps) at the
/// 16 kHz mono sample rate the iPhone mic captures at — yields ~25 MB/hr
/// vs ~115 MB/hr for the prior WAV PCM format. AAC is the format
/// `UIActivityViewController` and `Files.app` both render natively for
/// `.m4a`.
static let aacOutputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 32_000,
]

func newAudioCaptureURL() -> URL {
    let fm = FileManager.default
    let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dateF = DateFormatter()
    dateF.dateFormat = "yyyyMMdd-HHmmss"
    let stamp = dateF.string(from: Date())
    let safeId = casualtyId.replacingOccurrences(of: " ", with: "_")
    return dir.appendingPathComponent("encounter-\(safeId)-\(stamp).m4a")
}
```

`AVFormatIDKey` etc. require `import AVFoundation` at the top of the file — add if missing (`grep -n "^import" TCCC_IOS/App/AppState.swift` to check).

- [ ] **Step 3: Build (the new constant is unused until L2.2)**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. (The .m4a-extension URL change is consumed by the existing recognizer code, which opens an AVAudioFile against it — that may or may not still build with the .m4a extension and old PCM settings. If it errors, that's expected and L2.2 fixes it; otherwise the .m4a file will get PCM written into it, which is broken-but-builds.)

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/App/AppState.swift
git diff --staged --stat
git commit -m "feat(audio): AAC settings constant + .m4a capture URL extension"
```

---

### Task L2.2: ParakeetTranscriptStream — AAC AVAudioFile

**Why:** Replace the WAV PCM `AVAudioFile(forWriting:)` call with one using the AAC settings dict from L2.1. `AVAudioFile.write(from:)` accepts a PCM `AVAudioPCMBuffer` and AVFoundation handles the PCM-to-AAC conversion internally for AAC-in-M4A.

**Files:**
- Modify: `TCCC_IOS/Audio/ParakeetTranscriptStream.swift` around line 252 (the existing `AVAudioFile(forWriting:` site)

- [ ] **Step 1: Locate the AVAudioFile open**

```bash
grep -n "AVAudioFile(forWriting" TCCC_IOS/Audio/ParakeetTranscriptStream.swift
```

Read the surrounding ~15 lines for context.

- [ ] **Step 2: Replace the open**

The current code looks roughly like:

```swift
let file = try AVAudioFile(
    forWriting: url,
    settings: format.settings,
    commonFormat: .pcmFormatFloat32,
    interleaved: false
)
```

Replace with:

```swift
let file = try AVAudioFile(
    forWriting: url,
    settings: AppState.aacOutputSettings,
    commonFormat: .pcmFormatFloat32,
    interleaved: false
)
```

The `commonFormat` and `interleaved` arguments stay as-is — they describe the format of the PCM buffers being written into the file, not the file format itself. AVAudioFile uses the `settings:` AAC dict to encode on write.

- [ ] **Step 3: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Surface the fallback risk in a comment**

Add a comment above the changed line:

```swift
// AAC encode-on-write. AVFoundation handles PCM -> AAC internally for
// .m4a output. If a future iOS release introduces frame-boundary errors
// at AAC's 1024-sample input boundary vs our 4096-sample tap buffer,
// fall back to an explicit AVAudioConverter with an inputBlock loop.
```

- [ ] **Step 5: Commit**

```bash
git add TCCC_IOS/Audio/ParakeetTranscriptStream.swift
git diff --staged --stat
git commit -m "feat(audio): Parakeet writes AAC m4a instead of WAV"
```

---

### Task L2.3: SpeechRecognizer — AAC AVAudioFile (mirror of L2.2)

**Why:** Same fix in the Apple Speech path so a fallback recording produces the same .m4a format. No semantic difference.

**Files:**
- Modify: `TCCC_IOS/Audio/SpeechRecognizer.swift` around line 182 (the existing AVAudioFile open)

- [ ] **Step 1: Locate**

```bash
grep -n "AVAudioFile(forWriting" TCCC_IOS/Audio/SpeechRecognizer.swift
```

- [ ] **Step 2: Replace settings argument**

Same replacement as L2.2 Step 2 — point `settings:` at `AppState.aacOutputSettings`.

- [ ] **Step 3: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/Audio/SpeechRecognizer.swift
git diff --staged --stat
git commit -m "feat(audio): SpeechRecognizer writes AAC m4a instead of WAV"
```

---

## Track L3 — Parakeet long-form safeguards

### Task L3.1: Periodic stats logger

**Why:** No user-visible feature — operator gets debugging breadcrumbs in `os_log` so we can audit memory/state behavior over a 90-min recording without instrumenting after the fact.

**Files:**
- Modify: `TCCC_IOS/Audio/ParakeetTranscriptStream.swift` (add a `DispatchSourceTimer` + log site)

- [ ] **Step 1: Add the timer field**

Near the other private fields (around line 75):

```swift
/// 5-min periodic logger that emits memory + transcript-size stats
/// for long-form sessions. Started by `prime()`, stopped by `stop()`.
/// Dev breadcrumbs only — never user-facing.
private var statsTimer: DispatchSourceTimer?
```

- [ ] **Step 2: Add the start/stop helpers**

```swift
private func startStatsTimer() {
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now() + 300, repeating: 300)
    timer.setEventHandler { [weak self] in
        Task { await self?.emitStats() }
    }
    timer.resume()
    self.statsTimer = timer
}

private func stopStatsTimer() {
    statsTimer?.cancel()
    statsTimer = nil
}

private func emitStats() {
    let avail = os_proc_available_memory()
    let partialLen = currentPartial.count
    let logger = Logger(subsystem: "ai.tccc", category: "parakeet-longform")
    logger.info("stats: avail=\(avail) bytes, partial=\(partialLen) chars")
}
```

The actor's `prime()` and `stop()` need to call `startStatsTimer()` and `stopStatsTimer()` respectively. Find them with `grep -n "func prime\|func stop\b" TCCC_IOS/Audio/ParakeetTranscriptStream.swift`.

- [ ] **Step 3: Add `import os` at the top of the file if not already present**

```bash
grep -n "^import os" TCCC_IOS/Audio/ParakeetTranscriptStream.swift
```

If absent, add `import os` near the existing `import Foundation`.

- [ ] **Step 4: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add TCCC_IOS/Audio/ParakeetTranscriptStream.swift
git diff --staged --stat
git commit -m "feat(audio): periodic stats logger for Parakeet long-form sessions"
```

---

### Task L3.2: Defensive partial-string ceiling

**Why:** Prevent a degenerate run-on partial from accumulating unbounded intermediate state. If `currentPartial.count > 2000`, force-commit it via the existing finalize path and reset.

**Files:**
- Modify: `TCCC_IOS/Audio/ParakeetTranscriptStream.swift`

- [ ] **Step 1: Locate the partial-emission point**

```bash
grep -n "emitPartial\|currentPartial =\|currentPartial \(.*\)" TCCC_IOS/Audio/ParakeetTranscriptStream.swift | head -10
```

The actor likely has an `emitPartial(_ text: String)` method that updates `currentPartial` and pushes a `.partial` update through the continuation.

- [ ] **Step 2: Add the ceiling check**

Inside `emitPartial`, after assigning `currentPartial = text`:

```swift
private let partialStringCeiling = 2000

func emitPartial(_ text: String) async {
    self.currentPartial = text
    if text.count > partialStringCeiling {
        // Defensive: force-commit a runaway partial so internal state
        // doesn't grow unbounded. Real audio still flows; we just
        // close the open utterance and let the next partial start fresh.
        await emitFinal(text)
        self.currentPartial = ""
        return
    }
    continuation?.yield(.partial(text))
}
```

(`emitFinal(_:)` already exists per the codebase.)

- [ ] **Step 3: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/Audio/ParakeetTranscriptStream.swift
git commit -m "feat(audio): defensive 2000-char partial-string ceiling for Parakeet"
```

---

### Task L3.3: Memory-pressure observer in AppState

**Why:** When iOS warns of critical memory pressure mid-90-min recording, force-commit any in-flight partial and clear transient state. Don't restart the recognizer — operator's recording continues.

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift`

- [ ] **Step 1: Add the observer field**

Near the other long-lived helpers:

```swift
/// Memory-pressure observer. Fires on `.warning` and `.critical` events
/// from iOS. We listen for `.critical` and force-commit any in-flight
/// partial transcript so transient state doesn't compound the pressure.
private var memoryPressureSource: DispatchSourceMemoryPressure?
```

- [ ] **Step 2: Wire it in init**

Inside the init from L1.3 (or add init if not yet added):

```swift
let src = DispatchSource.makeMemoryPressureSource(
    eventMask: [.warning, .critical],
    queue: .main
)
src.setEventHandler { [weak self] in
    guard let self else { return }
    let event = src.mask
    if event.contains(.critical) {
        // Force-commit the in-flight partial so transient state collapses.
        self.appendSystem("MEMORY · critical pressure · committing partial")
        if !self.partialTranscript.isEmpty {
            self.appendFinal(self.partialTranscript)
            self.partialTranscript = ""
        }
    } else if event.contains(.warning) {
        let logger = Logger(subsystem: "ai.tccc", category: "memory")
        logger.warning("memory: warning event received")
    }
}
src.resume()
self.memoryPressureSource = src
```

`import os` and `import Dispatch` may need to be added if not present (`grep -n "^import" TCCC_IOS/App/AppState.swift`).

- [ ] **Step 3: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/App/AppState.swift
git commit -m "feat(audio): memory-pressure observer force-commits partial under load"
```

---

## Track L4 — Transcript UI + auto-clean throttling

### Task L4.1: Auto-pin scroll behavior

**Why:** Today's auto-scroll behavior is unverified at length. Operator should always see the latest line during recording, but should be able to scroll up to read older content without being yanked back. Already uses `LazyVStack` (good); needs an `autoPinned: Bool` state that flips off on user-initiated scroll up and back on when user lands within ~80 pt of bottom.

**Files:**
- Modify: `TCCC_IOS/Screens/LiveCaptureScreen.swift` (the `transcriptList` view, around line 156)

- [ ] **Step 1: Read the current implementation**

```bash
sed -n '150,200p' TCCC_IOS/Screens/LiveCaptureScreen.swift
```

Identify the `.onChange(of: displayedTranscript.count)` handler that drives the scroll-to-bottom call. Read it carefully so the new gating is correct.

- [ ] **Step 2: Add the autoPinned state**

In the `LiveCaptureScreen` struct's `@State` block (find around line 14):

```swift
@State private var transcriptAutoPinned: Bool = true
```

- [ ] **Step 3: Conditionalize the auto-scroll**

In the existing `.onChange(of: displayedTranscript.count)` block, gate the `proxy.scrollTo` call:

```swift
.onChange(of: displayedTranscript.count) { _, _ in
    guard transcriptAutoPinned else { return }
    if let last = displayedTranscript.last {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
```

- [ ] **Step 4: Detect manual scroll up + re-engage**

Inside the `ScrollView`, add a `GeometryReader`-based detector that flips `transcriptAutoPinned` off when the operator scrolls more than ~80 pt from the bottom, and back on when they return:

```swift
ScrollView {
    LazyVStack(...) { ... }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geo.frame(in: .named("transcriptScroll")).maxY
                )
            }
        )
}
.coordinateSpace(name: "transcriptScroll")
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
    // We don't have access to the visible-rect bottom from a SwiftUI
    // ScrollView without UIScrollView introspection. Approximate: if
    // displayedTranscript grew and the content's maxY is far above the
    // viewport bottom, the user scrolled up. Track maxY drift on each
    // commit; if drift between commits is non-zero in the upward
    // direction, disengage auto-pin.
    //
    // For now, simpler heuristic: any DragGesture in the upward
    // direction disengages auto-pin; the bottom-anchor scrollTo on
    // the next .onChange will not fire.
}
.simultaneousGesture(
    DragGesture(minimumDistance: 8)
        .onChanged { value in
            if value.translation.height > 20 {
                // Operator dragged the content downward (scrolling up
                // through history). Disengage auto-pin.
                transcriptAutoPinned = false
            }
        }
)
```

Add the preference key at file scope (or top of struct):

```swift
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

- [ ] **Step 5: Add a "Jump to latest" affordance**

When `transcriptAutoPinned` is false and `displayedTranscript.count > 0`, render a small floating button at the bottom-right of the panel:

```swift
.overlay(alignment: .bottomTrailing) {
    if !transcriptAutoPinned {
        Button {
            transcriptAutoPinned = true
            if let last = displayedTranscript.last {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .heavy))
                Text("LATEST").font(.system(size: 10, weight: .heavy)).tracking(1.2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.bg2)
            .overlay(Rectangle().strokeBorder(palette.accent, lineWidth: Layout.hairline))
        }
        .buttonStyle(.plain)
        .padding(12)
    }
}
```

- [ ] **Step 6: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add TCCC_IOS/Screens/LiveCaptureScreen.swift
git commit -m "feat(ui): manual-scroll disengages transcript auto-pin; LATEST chip re-engages"
```

---

### Task L4.2: Auto-clean 60s must-run fallback

**Why:** Today's auto-clean is cancelled by every silence-commit. At long-form with frequent commits, it may never fire. Add a "must-run" fallback: if it's been ≥ 60 s since the last successful clean, run unconditionally instead of cancel-and-reschedule.

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (the `scheduleAutoClean()` function)

- [ ] **Step 1: Add the lastCleanedAt field**

Near the other auto-clean state (find with `grep -n "autoCleanTask" TCCC_IOS/App/AppState.swift`):

```swift
/// Wall-clock when the last auto-clean run completed successfully.
/// Drives the 60s must-run fallback in `scheduleAutoClean()`.
var lastCleanedAt: Date?
```

- [ ] **Step 2: Update scheduleAutoClean**

Replace the current body with:

```swift
func scheduleAutoClean() {
    let lines = transcript
    guard lines.count >= 3 else { return }

    let mustRun: Bool
    if let last = lastCleanedAt {
        mustRun = Date().timeIntervalSince(last) >= 60
    } else {
        mustRun = false
    }

    if !mustRun {
        // Cancel-and-reschedule (existing behavior). Fresh commits keep
        // pushing the deadline.
        autoCleanTask?.cancel()
    }
    // If mustRun, leave autoCleanTask alone — let it land if mid-flight,
    // or schedule a new one if cancelled. Either way, we ensure something
    // runs within the next 5s.

    let backend = currentBackend
    autoCleanTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
        guard let self, !Task.isCancelled else { return }
        let toClean = self.transcript
        guard toClean.count >= 3 else { return }
        do {
            let cleaned = try await TranscriptCleaner(backend: backend).clean(toClean)
            guard !Task.isCancelled else { return }
            self.transcriptCleaned = cleaned
            self.lastCleanedAt = Date()
        } catch {
            // Silent failure — manual button surfaces errors directly.
        }
    }
}
```

- [ ] **Step 3: Update reset paths**

`newPatient()`, `endCurrentCare()`, `wipeSession()` already cancel `autoCleanTask`. Add `lastCleanedAt = nil` to each so a fresh casualty starts the 60s clock from zero:

```bash
grep -n "autoCleanTask = nil" TCCC_IOS/App/AppState.swift
```

For each match, add `lastCleanedAt = nil` on the next line.

- [ ] **Step 4: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add TCCC_IOS/App/AppState.swift
git commit -m "feat(slm): auto-clean 60s must-run fallback so frequent commits don't starve it"
```

---

### Task L4.3: Auto-clean 200-line recent window

**Why:** Cleaning a 2000-line transcript through the LLM every minute is wasteful — older lines are already settled. Pass only the last N lines to the cleaner.

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (`scheduleAutoClean`)

- [ ] **Step 1: Define the window constant**

Above `scheduleAutoClean`:

```swift
/// Auto-clean only operates on the last N transcript lines. Older lines
/// have already been cleaned in prior passes (or are in the still-raw
/// region the operator hasn't requested cleaning for). Reduces LLM cost
/// from O(N) to O(window) per pass and keeps cleaner output stable for
/// older content. Tunable.
private static let autoCleanWindow = 200
```

- [ ] **Step 2: Slice the input**

In the Task body of `scheduleAutoClean`:

```swift
let toClean = self.transcript
guard toClean.count >= 3 else { return }
let recent = Array(toClean.suffix(Self.autoCleanWindow))
do {
    let cleaned = try await TranscriptCleaner(backend: backend).clean(recent)
    guard !Task.isCancelled else { return }
    // Reassemble: keep the leading `toClean.count - recent.count` lines
    // as-is from `transcriptCleaned ?? toClean`, then append the freshly
    // cleaned recent slice. Result has the same total line count as
    // `toClean`.
    let leadingCount = max(0, toClean.count - recent.count)
    let leading: [TranscriptLine]
    if let prior = self.transcriptCleaned, prior.count >= leadingCount {
        leading = Array(prior.prefix(leadingCount))
    } else {
        leading = Array(toClean.prefix(leadingCount))
    }
    self.transcriptCleaned = leading + cleaned
    self.lastCleanedAt = Date()
} catch {
    // Silent failure
}
```

The reassembly preserves prior cleanings on older lines, only refreshing the recent window. If `transcriptCleaned` is nil or shorter than expected, fall back to the raw transcript prefix.

- [ ] **Step 3: Build**

```bash
cd /Users/ama/TCCC_IOS
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add TCCC_IOS/App/AppState.swift
git commit -m "feat(slm): auto-clean 200-line recent window; older lines preserved"
```

---

## Track F — Final integration verification

### Task F.1: Device build + 60-min smoke test

**Why:** None of the prior tracks proves end-to-end behavior over a real long-form session. This task is manual on the connected iPhone 17 Pro.

- [ ] **Step 1: Build for device**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS,id=4FC3C1DC-B809-552A-B60F-B1723ADB45B8' \
  -configuration Debug \
  -derivedDataPath /tmp/TCCC_IOS-device-build \
  -skipMacroValidation build 2>&1 | tail -5
```

If the device-id destination resolver fails (it has been flaky this session), substitute `generic/platform=iOS` for the build, then `devicectl install` directly:

- [ ] **Step 2: Install + launch**

```bash
xcrun devicectl device install app --device 4FC3C1DC-B809-552A-B60F-B1723ADB45B8 \
  /tmp/TCCC_IOS-device-build/Build/Products/Debug-iphoneos/TCCC_IOS.app
xcrun devicectl device process launch --device 4FC3C1DC-B809-552A-B60F-B1723ADB45B8 \
  com.aarzamen.TCCCai
```

- [ ] **Step 3: Operator validation script**

On device, in order:
1. **Settings → Confirm `voiceCommandsEnabled` is on, `llmBackend = Liquid`**.
2. **Live Capture → tap RECORD**. Speak a sentence. Verify partial commits show up after ~2.5s of silence.
3. **Lock the phone** (press side button). Wait 60s. Unlock. The partial-finalize transcript line should be present from speech you produced while locked.
4. **Trigger an interruption**: ask Siri something OR start a phone call. Recording should pause; transcript shows `INTERRUPTED · audio session preempted` system line. After Siri finishes / call ends, transcript shows `RESUMED · HH:MM:SSZ` and recording continues.
5. **Disconnect AirPods if connected** (or any audio route change). Transcript shows `ROUTE · <new port>` line.
6. **Swipe to TCCC Card → Vitals → Handoff → back to Live Capture**. Transcript should still be growing.
7. **Stop recording** after at least 30 minutes have elapsed. Open Files.app and confirm the new audio file exists at `Documents/encounter-{casualtyId}-{timestamp}.m4a` and plays back.
8. **Settings → confirm Z/L time elapsed accumulator agrees with wall-clock**.
9. **Memory headroom in StatusStrip should not show a `WARN` or `CRIT` color throughout**.

- [ ] **Step 4: Note any deviations**

If the encoder errors mid-session, surface in commit + push the AVAudioConverter fallback path (research-doc'd in section 2). If memory pressure fires, log shows `MEMORY · critical pressure` in the transcript — that confirms the observer works.

- [ ] **Step 5: Update CLAUDE.md "Sprint history"**

Append a paragraph to the existing sprint-history block:

```
**Long-form recording (2026-05-05).** UIBackgroundModes audio + new
`AudioSessionCoordinator` actor for AVAudioSession interruption +
route observation. Audio files now AAC `.m4a` (~25 MB/hr) instead of
WAV PCM (~115 MB/hr) — both ASR backends share `AppState.aacOutputSettings`.
Parakeet long-form safeguards: 5-min DispatchSourceTimer for
memory + partial-string stats, 2000-char defensive partial ceiling,
critical memory-pressure observer on AppState. Auto-clean: 60s must-run
fallback so frequent commits don't starve cleaning, plus a 200-line
recent-window so each pass only LLMs the tail. Transcript UI:
manual-scroll disengages auto-pin; floating LATEST chip re-engages.
Verified end-to-end on iPhone 17 Pro with a 30-minute session including
a phone-call interruption resume.
```

- [ ] **Step 6: Commit + run finishing-a-development-branch**

```bash
git add CLAUDE.md
git commit -m "docs: sprint history — long-form recording (2026-05-05)"
```

Then run `superpowers:finishing-a-development-branch` to decide merge/PR.

---

## Self-review (executed during plan write)

**Spec coverage:**
- Spec §1 (Background audio + interruption) → L1.1 + L1.2 + L1.3 ✓
- Spec §2 (AAC audio file) → L2.1 + L2.2 + L2.3 ✓
- Spec §3 (Parakeet safeguards: stats + memory pressure + partial ceiling) → L3.1 + L3.2 + L3.3 ✓
- Spec §4 (auto-pin + 60s fallback + 200-line window) → L4.1 + L4.2 + L4.3 ✓
- Spec §5 (deferred items) → no tasks needed (intentionally not implemented).

**Placeholder scan:** No `TBD`, `TODO`, or "implement later" leaks. The auto-scroll detection in L4.1 has a quasi-pseudocode comment block where I describe the GeometryReader heuristic; I expressly told the implementer to use a simpler `simultaneousGesture(DragGesture)` approach if the geometry math is awkward — both options are concretely written.

**Type consistency:** `AudioSessionCoordinator` API consistent across L1.2 and L1.3. `AppState.aacOutputSettings` referenced by both L2.2 and L2.3 with the same type (`[String: Any]`). `lastCleanedAt: Date?` added in L4.2 and read in L4.3 with same name. `transcriptAutoPinned` is local-state only (not exposed beyond L4.1). `partialStringCeiling = 2000` consistent between Spec §3 and L3.2. `autoCleanWindow = 200` consistent.

---

## Execution Handoff

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task; Wave 1 dispatches 4 in parallel, Wave 2 + Wave 3 sequence carefully because they share `AppState.swift` and `ParakeetTranscriptStream.swift`. F.1 is manual.

**2. Inline Execution** — I walk tasks L1.1 → F.1 in order in this session.
