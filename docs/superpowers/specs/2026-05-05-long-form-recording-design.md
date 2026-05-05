# Long-Form Recording — Design Spec

> Date: 2026-05-05
> Status: Approved (sections 1-5), pending spec review before implementation plan
> Owner: TCCC.ai iOS

## Goal

Make the app's recording path durable and operator-trustable for 30–90 minute sessions ("medium-form") — a debrief, a training scenario, an OR-side huddle — without changing the existing UI mode or the engine extraction pipeline. The same Live Capture screen handles both a 5-minute TCCC pass and a 90-minute meeting; the engine stays on and harmlessly extracts what it can.

## Scope decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Mode | **Same path as TCCC**, engine still runs | Cheapest mental model; engine is harmless on non-TCCC content |
| Speakers | **Single voice** | Diarization is a separate model layer; not needed for medic-narration use case |
| Duration target | **30–90 min** | Apple Speech 1-min ceiling becomes a problem at this length; Parakeet doesn't have one |
| Primary ASR backend | **Parakeet** | Streaming-native, no per-request ceiling; the model the operator has invested in |
| Apple Speech role | **Fallback only** | Used when Parakeet won't load; long-form auto-restart engineering is deferred |
| Audio file format | **AAC `.m4a`** | ~25 MB/hr vs ~115 MB/hr for WAV; UIActivityViewController handles natively |
| Backgrounding | **Background audio entitlement** | Recording survives screen-lock and app-switch; iOS Dynamic Island shows the system "Recording" pill for free |
| TCCC vocabulary biasing | **Deferred** | User flagged explicitly as a separate, later concern |
| Diarization | **Deferred** | Not needed for single-voice |
| App-killed-by-OS recovery | **Deferred** | Separate persistence story |

## Architecture

Five sections, each implemented as a small set of focused edits or one new file. No new screens, no new top-level state machines.

---

### 1. Background audio + interruption handling

**1a. Background audio entitlement.**

Add to `project.yml`:

```yaml
infoPlist:
  UIBackgroundModes:
    - audio
```

Effect: `AVAudioEngine` continues running when backgrounded / screen locked. iOS surfaces the system "Recording" pill in the Dynamic Island — operator gets a continuous "this is recording" reminder even when not in the app. No code change needed beyond the Info.plist key.

**1b. AVAudioSession interruption observer.**

A new `AudioSessionCoordinator` actor subscribes to:

- `AVAudioSession.interruptionNotification`
  - On `.began`: pause the recognizer (call `recognizer.stopImmediate()` but DO NOT `unprime()`), set `state.isRecording = false`, snapshot the partial transcript via the existing silence-debounce committer, retain a `wasRunningAtInterruption: Bool = true` flag inside the coordinator.
  - On `.ended` with `.shouldResume`: re-prime the engine, restart the recognizer's stream, append a system transcript line `[INTERRUPTED · resumed at HH:MM:SSZ]`, set `state.isRecording = true`.
  - On `.ended` without `.shouldResume`: surface a banner ("Recording interrupted — tap RECORD to resume"), leave the recognizer parked.

- `AVAudioSession.routeChangeNotification`
  - On any change: append a system transcript line `[ROUTE · {newPort}]` (e.g. headphone disconnect mid-session). Don't pause.

The coordinator is owned by `AppState` (long-lived) so observers stay registered across `LiveCaptureScreen` onAppear/onDisappear cycles.

**1c. Recognizer lifecycle change.**

The `LiveCaptureScreen.onDisappear` keep-alive logic shipped in sprint 3 stays. The interruption coordinator is a new layer on top — it knows how to gracefully pause/resume regardless of which screen is foregrounded.

**Out of section 1:** App-killed-by-OS recovery is not in scope.

---

### 2. AAC audio file

**2a. Encode pipeline.**

Replace the current `AVAudioFile(forWriting: url, settings: ...)` PCM-to-WAV write in both `ParakeetTranscriptStream.swift` and `SpeechRecognizer.swift` with a PCM-to-AAC pipeline.

Concrete shape:

```swift
// On start():
let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 32_000,
]
let aacFile = try AVAudioFile(
    forWriting: url, // .m4a extension
    settings: outputSettings,
    commonFormat: .pcmFormatFloat32,
    interleaved: false
)
```

`AVAudioFile.write(from:)` accepts a PCM `AVAudioPCMBuffer` and internally converts to the file's compressed format using AVFoundation's built-in encoder. No manual `AVAudioConverter` needed — this is the simpler path that works for AAC-in-CAF/M4A. (Verify on device: `AVAudioFile.write(from:)` with AAC settings works in our streaming-tap context. If it doesn't, fall back to explicit `AVAudioConverter` per the original sketch.)

**2b. File path + lifecycle.**

`AppState.newAudioCaptureURL()` returns `Documents/encounter-{casualtyId}-{stamp}.m4a` (was `.wav`). `ProtectedWrite.createEmpty(at:)` is called immediately before `AVAudioFile(forWriting:)` so the file inherits `.completeFileProtection`. On `recognizer.stop()`, `AVAudioFile` is dropped (closes the encoder); `ProtectedWrite.markProtected(at:)` is called for defensive idempotence.

**2c. Compatibility.**

Old `.wav` files referenced by historical `state.lastRecordingURL` values stay where they are — no migration. The new path lands `.m4a` for any session started after the change. Export bundles ship whatever extension the most recent recording has.

**Risk to surface during implementation:** if `AVAudioFile.write(from:)` rejects the streaming PCM buffer at AAC's frame boundaries (1024 samples vs the 4096-sample tap buffer), we fall back to an explicit `AVAudioConverter` with a buffered input loop. Test with a known-good 5-minute recording before declaring 90 min works.

---

### 3. Parakeet long-form durability

**3a. Audit then safeguard, not pre-engineer.**

FluidAudio's `StreamingEouAsrManager` is designed for streaming, but our usage history is short. Don't pre-emptively re-architect. Add cheap insurance and observe.

**3b. Concrete safeguards:**

- **Periodic stats logging.** A `DispatchSourceTimer` fires every 5 minutes during recording. Logs to `os_log` (dev-only): `os_proc_available_memory()`, `state.transcript.count`, current partial-string length. Not user-facing.
- **Memory pressure observer.** `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` on `AppState`. On `.critical`: force-commit the in-flight partial via the existing `forceFinalize()` path. Do NOT restart the recognizer or wipe transcript. The auto-clean LLM and engine are untouched.
- **Defensive partial-string ceiling.** If `currentPartial.count > 2000`, force-commit and reset. Prevents one degenerate run-on partial from accumulating unbounded intermediate state.

**3c. No automatic recognizer restart.** If Parakeet errors mid-session, surface an error banner. Operator hits RECORD again to restart. Silent restart inside a 90-min meeting is worse than a visible failure.

**3d. Out of section 3:** No fine-tuning, no model swap, no re-quantization. TCCC vocabulary biasing is its own (deferred) sprint.

---

### 4. Transcript UI scaling + auto-clean throttling

**4a. Audit current state first.**

Before changes: read `LiveCaptureScreen.transcriptList` and confirm it uses `LazyVStack` inside a `ScrollView`. SwiftUI's lazy variant virtualizes off-screen rows. If it's a plain `VStack`, switch it.

**4b. Auto-scroll behavior.**

When `state.transcript` grows, the latest line should remain visible (auto-pin to bottom). When the operator manually scrolls up, the auto-pin disengages until they scroll back to within ~80 pt of the bottom. Implementation via `ScrollViewReader.scrollTo(_:)` keyed on the last transcript line's `id`, gated by a `@State private var autoPinned: Bool = true` that toggles on user-initiated scroll.

**4c. Auto-clean fallback.**

Today's auto-clean (sprint 3): scheduled 5s after each silence-commit; cancelled by the next silence-commit. At long-form with frequent commits, it may never actually fire.

Add a "must-run" fallback to `AppState.scheduleAutoClean()`:
- New field: `var lastCleanedAt: Date? = nil`
- When scheduling, check: if `lastCleanedAt == nil` OR `Date().timeIntervalSince(lastCleanedAt) >= 60`, run unconditionally instead of cancelling. Otherwise cancel-and-reschedule as today.
- After a successful clean: `lastCleanedAt = Date()`.

> **Note: this is what voice-activity detection (VAD) is for.** The 60s
> wall-clock fallback is a coarse stand-in. The proper solution is to
> detect actual speaker silence vs. ambient noise and fire the cleaner
> during real pauses. VAD is deferred (see section 5); the fallback gets
> us reliable cleaning at long-form without it.

**4d. Auto-clean window.**

Cleaning the entire 2000-line transcript through the LLM every minute is wasteful — older lines are already cleaned. New constant: `private let autoCleanRecentLineCount = 200`. Pass only the last N lines to `TranscriptCleaner.clean(_:)`. Older lines stay as previously cleaned. This both reduces LLM cost and keeps cleaner output stable for older content.

**4e. Out of section 4:** Pagination, search, speaker labels, editable transcript.

---

### 5. Out of scope (explicit)

| Item | Reason | Deferred to |
|---|---|---|
| TCCC vocabulary biasing (Apple Speech `contextualStrings`, LLM glossary block) | User flagged separately | Future sprint |
| Apple Speech long-form auto-restart at 1-min boundary | Apple Speech is fallback-only after Parakeet became default | Future sprint, low priority |
| Diarization (multi-speaker labels) | Single-voice scope | If multi-speaker becomes a real need |
| App-killed-by-OS session recovery | Separate persistence story | Future sprint |
| Background-recording battery audit + low-power mode toggle | Operator accepts the high battery cost; not optimizing | If field testing flips this preference |
| Voice-activity detection (VAD) | The proper fix for "when to fire auto-clean" and chunk boundaries; the 60s wall-clock fallback in §4c is a stand-in. Also enables future: chunked recording rotation, silence-trimming the audio file, smarter EOU. | Future sprint |
| Pagination / search / editable transcript | Operator UI features | Future sprint |

---

## Test plan (high-level)

Per implementation plan, but spec-level signals:

- Manual: 60-min recording on iPhone 17 Pro with phone locked for 30 min in the middle. Recording should survive; transcript on resume should show `[INTERRUPTED · resumed]` lines for the lock-screen transitions if any interruption fired.
- Manual: phone-call mid-recording. Recording pauses, resumes after call ends, system transcript line marks the gap.
- Manual: airpods-disconnect mid-recording. System transcript line, no pause.
- Memory: 90-min recording with periodic stats logged; available memory should not trend down (steady state, modulo transcript array growth).
- File: 90-min `.m4a` should be ~40 MB and play back cleanly in Files app and via UIActivityViewController.

## Implementation phasing

The implementation plan that follows this spec partitions roughly:

1. Background entitlement + AVAudioSession coordinator (section 1)
2. AAC audio file (section 2)
3. Parakeet safeguards (section 3)
4. Transcript UI + auto-clean throttling (section 4)

Sections 1, 2, 4 touch disjoint files and parallelize; section 3 is small enough to fold into any of them or run alone.

---

## Open questions

None at spec-write time. If implementation surfaces an `AVAudioFile.write(from:)`-vs-AAC-buffer-boundary issue (section 2 risk), the plan will fall back to explicit `AVAudioConverter`.
