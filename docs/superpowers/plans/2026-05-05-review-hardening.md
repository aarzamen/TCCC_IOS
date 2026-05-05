# Review-Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address the highest-risk findings from ChatGPT's review before resuming the speech-to-text work — make the app safe for an operator to trust, harden clinical/LLM correctness, fix the audio race + ordering bug, raise hit-target compliance, and tighten release engineering.

**Architecture:** Five mostly-independent tracks (A–E) that can be dispatched to parallel agents. Each track ends in a green build + `swift test`. Track ordering is **not** strict — agents work tracks concurrently on a single branch (`hardening-2026-05-05`); the only cross-track touchpoint is `AppState.swift`, which Track A and Track B both edit (Track A first, then B rebases).

**Tech Stack:** Swift 6.2 / SwiftUI / TCCCKit SPM package / XCTest / xcodegen / xcodebuild / `os.allocated_unfair_lock`.

---

## Out of scope

These review items are intentionally **not** in this plan — they're either bigger lifts to be planned separately or the existing CLAUDE.md "What's left" list already tracks them:

- DD-1380 PDF generation (CLAUDE.md item 2; needs a clean form image).
- Tap-to-edit §C grid cells (CLAUDE.md item 1).
- Custom stroke icon library (CLAUDE.md item 11).
- Inter Tight + JetBrains Mono fonts (CLAUDE.md item 10).
- Multi-casualty UI (CLAUDE.md item 12).
- Real audio export bundle / zipping (CLAUDE.md item 13).
- LFM2 / Qwen MLX backends actually shipping (CLAUDE.md item 7).
- "Move report/business logic out of app target into TCCCKit" (review critique). The pieces (`NineLineForm`, `HandoffData`, `ExtractedFact`) carry view-model state and SwiftUI types; relocating them is a structural refactor that should follow its own plan, not be folded in here.

## Parallelization map

```
Track A — Safety hardening (5 tasks)        ┐
Track B — LLM / clinical correctness (5)    ├ A → B (B rebases A's AppState)
Track C — Audio + concurrency (2 tasks)     ┤ C, D, E independent of A/B and each other
Track D — Hit-target compliance (3 tasks)   ┤
Track E — Release engineering (3 tasks)     ┘
Track F — Final integration + verification  (after A–E)
```

Subagent-driven dispatch order (single message): **A1, C1, C2, D1+D2+D3 (single agent — same Layout.swift edit), E1+E2 (single agent — same files), E3.** When A finishes, dispatch **B1, B2, B3, B4** in parallel, then **B5** sequentially. Track F runs last.

Total: 19 task-steps across 6 tracks.

---

## Track A — Safety hardening

### Task A1: Explicit GPS source state

**Why:** `AppState.swift:228` initializes `gpsLatitude = 34.5267`, `gpsLongitude = 69.1729` — these get fed straight into `NineLineForm.derive(...)` as Line 1 LOCATION. With no real GPS source, the app generates a 9-line that *looks* authoritative but is fabricated. The fix: model the source explicitly so the UI can render a `DEMO`/`MANUAL`/`NONE` badge and the 9-line either refuses to populate Line 1 or marks it as unverified.

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (lines 228–229 area, plus new types near other `enum`s around 200)
- Modify: `TCCC_IOS/App/NineLineForm.swift` (line 22 — `derive(...)`)
- Modify: `TCCC_IOS/Components/StatusStrip.swift` (add badge near MGRS chip — confirm with `grep`)
- Modify: `TCCC_IOS/Components/SettingsOverlay.swift` (operator profile section — add a "Location source" picker)

- [ ] **Step 1: Define `LocationSource` enum + replace raw lat/lon**

In `AppState.swift`, near the other top-level enums (around line 200), add:

```swift
enum LocationSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case none      // no fix — Line 1 must be marked UNVERIFIED
    case manual    // operator entered MGRS / lat-lon manually
    case demo      // bundled demo coordinates (training only)
    var id: String { rawValue }
    var badge: String {
        switch self {
        case .none:   "NO FIX"
        case .manual: "MANUAL"
        case .demo:   "DEMO"
        }
    }
}

struct LocationFix: Codable, Sendable, Equatable {
    var source: LocationSource
    var latitude: Double?
    var longitude: Double?
    /// True when source != .none AND lat/lon are non-nil.
    var isUsable: Bool { source != .none && latitude != nil && longitude != nil }
}
```

Replace the two existing fields:

```swift
// REMOVE
var gpsLatitude: Double = 34.5267
var gpsLongitude: Double = 69.1729

// REPLACE WITH
var locationFix: LocationFix = LocationFix(source: .none, latitude: nil, longitude: nil)
```

Search the whole repo with `grep -rn "gpsLatitude\|gpsLongitude" TCCC_IOS/` and update every callsite to read from `locationFix`.

- [ ] **Step 2: Update `NineLineForm.derive(...)` to honor source**

In `NineLineForm.swift` change the signature:

```swift
static func derive(
    from patients: [PatientState],
    locationFix: LocationFix,
    callsign: String = "DUSTOFF 6",
    frequency: String = "38.65 FM"
) -> NineLineForm {
```

Replace the Line 1 block:

```swift
let line1Value: String
let line1Status: NineLineEntry.Status
if let lat = locationFix.latitude, let lon = locationFix.longitude, locationFix.isUsable {
    line1Value = formattedLocation(lat: lat, lon: lon)
    line1Status = locationFix.source == .demo ? .demo : .auto
} else {
    line1Value = "UNVERIFIED — set location"
    line1Status = .pending
}
entries.append(.init(
    number: 1,
    label: "LOCATION",
    value: line1Value,
    icon: "mappin.and.ellipse",
    status: line1Status,
    isAuto: locationFix.source != .manual
))
```

Add `.demo` and `.pending` to `NineLineEntry.Status` if missing.

- [ ] **Step 3: StatusStrip badge**

Add a small badge next to the MGRS chip that renders `locationFix.source.badge` when source != `.none`. Color-code: `.demo` orange, `.manual` neutral, `.none` warning red.

- [ ] **Step 4: SettingsOverlay picker**

Under the operator-profile section, add a `Picker` over `LocationSource.allCases` bound to `state.locationFix.source`. When the user picks `.demo`, populate sample coords (e.g. 34.5267 / 69.1729 — same as today but explicitly labeled). When `.manual`, expose two `TextField`s for lat/lon.

- [ ] **Step 5: Verify build + `swift test`**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
swift test --package-path Packages/TCCCKit 2>&1 | tail -5
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: 697 package tests pass (no logic changes there). Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(safety): explicit LocationSource — no more silent Bagram default"
```

---

### Task A2: Protected-write helper + apply to every disk write

**Why:** CLAUDE.md hard constraint #3 promises NSFileProtectionComplete, but `HandoffData.writeJSON`, `writeVitalsCSV`, the audio `.wav` write in `ParakeetTranscriptStream` (and the Apple Speech path), and the (TODO) PDF write all currently use `.atomic` only. A casualty's identifying data hits disk in clear without Data Protection.

**Files:**
- Create: `TCCC_IOS/App/ProtectedWrite.swift`
- Modify: `TCCC_IOS/App/HandoffData.swift` (lines 369, 386 plus any other write paths — find with `grep -n "\.write(to:" TCCC_IOS/App/HandoffData.swift`)
- Modify: `TCCC_IOS/Audio/ParakeetTranscriptStream.swift` (audio file open)
- Modify: `TCCC_IOS/Audio/SpeechRecognizer.swift` if it also writes audio (verify with grep)

- [ ] **Step 1: Create `ProtectedWrite.swift`**

```swift
import Foundation

enum ProtectedWrite {
    /// Atomic + complete file protection. Use for any casualty-identifying artifact.
    static func data(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Create a placeholder file with complete protection so subsequent
    /// streamed writes (AVAudioFile, FileHandle.write) inherit it.
    static func createEmpty(at url: URL) throws {
        let attrs: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attrs)
        try (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }

    /// Mark an already-existing file complete-protected (idempotent).
    static func markProtected(at url: URL) throws {
        try (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }
}
```

- [ ] **Step 2: Replace `HandoffData.writeJSON` write**

```swift
// was: try data.write(to: url, options: [.atomic])
try ProtectedWrite.data(data, to: url)
```

Same for `writeVitalsCSV`. Audit the rest of HandoffData (transcript, audio share copy) and any other `.write(to:` callsite — every casualty file goes through `ProtectedWrite`.

- [ ] **Step 3: Audio capture file**

In `ParakeetTranscriptStream.swift` (and `SpeechRecognizer.swift` if it opens its own AVAudioFile), call `ProtectedWrite.createEmpty(at: url)` immediately before `AVAudioFile(forWriting: url, ...)`. After `audioFile = nil` (close), call `ProtectedWrite.markProtected(at: url)` to be defensive.

- [ ] **Step 4: Verify**

```bash
cd /Users/ama/TCCC_IOS
grep -rn "\.write(to:" TCCC_IOS/ Packages/TCCCKit/Sources/ | grep -v "ProtectedWrite.swift"
```

Expected: every remaining match is either a non-casualty file (e.g. a test fixture) or already routed through `ProtectedWrite`. Build + `swift test`.

- [ ] **Step 5: Commit**

```bash
git commit -am "fix(safety): NSFileProtectionComplete on every casualty disk write"
```

---

### Task A3: Unified destructive-action confirmation

**Why:** `SettingsOverlay.swift:431` calls `state.newPatient()` on a single tap (no hold). `state.newPatient()` at `AppState.swift:417` clears transcript, partial transcript, primaryPatient, allPatients, vitalsLog, narrative cache, and recording URL. CLAUDE.md hard constraint #4 says "Long-press only for destructive actions with visual progress fill." The `Wipe` button two lines down already follows the pattern — `New Cas` should too.

**Files:**
- Modify: `TCCC_IOS/Components/SettingsOverlay.swift` (lines ~430–440 — replace `BigButton` with a `HoldToConfirmButton` pattern; reuse the same one used by Wipe)
- (Verify pattern) `TCCC_IOS/Components/HoldToConfirmButton.swift` — if absent, the Wipe inline gesture is the template; lift it into a component.

- [ ] **Step 1: Find the Wipe gesture template**

```bash
grep -n "WIPE\|wipeProgress\|\.gesture(LongPress" TCCC_IOS/Components/SettingsOverlay.swift | head -20
```

Note the lines and the duration (CLAUDE.md says 3s for Wipe).

- [ ] **Step 2: Extract a reusable component**

If `HoldToConfirmButton.swift` doesn't exist, create it:

```swift
import SwiftUI

struct HoldToConfirmButton: View {
    let label: String
    let systemImage: String
    let style: BigButton.Style
    let holdSeconds: Double
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        BigButton(label, systemImage: systemImage, style: style) {}
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: geo.size.width * progress)
                        .allowsHitTesting(false)
                }
            }
            .gesture(
                LongPressGesture(minimumDuration: holdSeconds)
                    .onChanged { _ in startProgress() }
                    .onEnded { _ in
                        progress = 1
                        action()
                        Task { try? await Task.sleep(nanoseconds: 200_000_000); progress = 0 }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4).onEnded { _ in cancelProgress() }
            )
    }

    private func startProgress() {
        task?.cancel()
        let start = Date()
        task = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                progress = min(elapsed / holdSeconds, 1)
                if progress >= 1 { return }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func cancelProgress() {
        task?.cancel()
        progress = 0
    }
}
```

(If a `HoldToConfirmButton` already exists, reuse and skip this step.)

- [ ] **Step 3: Replace single-tap NEW CAS**

In `SettingsOverlay.swift:431`:

```swift
HoldToConfirmButton(
    label: "New Cas",
    systemImage: "person.crop.circle.badge.plus",
    style: .standard,
    holdSeconds: 2
) {
    state.newPatient()
    state.settingsOpen = false
}
```

(2s hold, matching the existing TRANSMIT hold per CLAUDE.md.)

- [ ] **Step 4: Audit other destructive paths**

```bash
grep -rn "newPatient\|wipe\|removeAll" TCCC_IOS/Components/ TCCC_IOS/Chrome/ TCCC_IOS/Screens/ \
  | grep -v "\.swift:.*//\|_test\.swift\|Tests\.swift"
```

For each callsite that ends an encounter or clears state, confirm it goes through a hold-confirm path or is a programmatic helper not exposed to the UI.

- [ ] **Step 5: Commit**

```bash
git commit -am "fix(safety): hold-to-confirm on NEW CAS, matching WIPE pattern"
```

---

### Task A4: Gate non-functional egress destinations

**Why:** `HandoffDestination.swift` defines `.atak`, `.medhub`, `.qr`, `.nfc`. Only `.qr` actually does anything; the others are visual stubs. `HandoffScreen.swift:610` logs a `TRANSMIT · ATAK · 14:23Z` system line for any selected destination, which an operator could plausibly read as "the casualty packet was sent." That's a misleading affordance in a clinical context.

**Files:**
- Modify: `TCCC_IOS/App/HandoffDestination.swift`
- Modify: `TCCC_IOS/Screens/HandoffScreen.swift` (line 610 area + the destination grid)

- [ ] **Step 1: Add capability flag**

```swift
enum HandoffDestination: String, CaseIterable, Sendable {
    case atak
    case medhub
    case qr
    case nfc

    /// True when this destination has a real implementation that actually
    /// moves data off-device. False = visual placeholder (RF Ghost: no networking
    /// framework wired). Selecting a non-functional destination MUST NOT log a
    /// success-shaped TRANSMIT line.
    var isFunctional: Bool {
        switch self {
        case .qr: true
        case .atak, .medhub, .nfc: false
        }
    }

    var displayName: String { /* unchanged */ }
    var symbol: String { /* unchanged */ }
}
```

- [ ] **Step 2: Block transmit + relabel logging**

In `HandoffScreen.swift:610`:

```swift
private func completeTransmit() {
    guard isTransmitting else { return }
    isTransmitting = false
    transmitProgress = 1
    let dest = state.selectedHandoffDestination
    let stamp = HandoffSummary.formatTime(Date())

    if dest.isFunctional {
        state.appendSystem("TRANSMIT · \(dest.displayName) · \(stamp)")
        if dest == .qr { state.qrOverlayVisible = true }
    } else {
        state.appendSystem("TRANSMIT BLOCKED · \(dest.displayName) NOT WIRED · \(stamp)")
    }
    // ... rest unchanged
}
```

- [ ] **Step 3: Visually mark non-functional cards**

In the destination grid (find with `grep -n "HandoffDestination" TCCC_IOS/Screens/HandoffScreen.swift`), add a `PEND` corner badge or strikethrough on cards where `!destination.isFunctional`. Disable selection — or allow selection but show a banner: "Destination not wired in this build — use QR · OFFLINE."

- [ ] **Step 4: Commit**

```bash
git commit -am "fix(safety): mark ATAK/MEDHUB/NFC as non-functional, block fake TRANSMIT log"
```

---

### Task A5: Remove fabricated facts from Handoff

**Why:** `HandoffData.swift:142` maps any `.urgent` classification to the literal string `"Hemorrhagic shock · class III"` — an operational diagnosis the engine never emitted. `HandoffData.swift:256` always appends a `MEDEVAC requested` row to the timeline regardless of whether the operator actually sent one. Both create artifacts that look like assessment data but are static UI copy.

**Files:**
- Modify: `TCCC_IOS/App/HandoffData.swift` (lines 142–151 and 256–265)

- [ ] **Step 1: Replace fabricated `criticalValue`**

```swift
private static func criticalValue(for classification: Classification?) -> String {
    // Show the engine's actual classification — do not invent a clinical
    // diagnosis the extractor never emitted.
    switch classification {
    case .urgent:           "URGENT"
    case .urgentSurgical:   "URGENT SURGICAL"
    case .priority:         "PRIORITY"
    case .routine:          "ROUTINE"
    case .expectant:        "EXPECTANT"
    case .none:             "PENDING"
    }
}
```

- [ ] **Step 2: Synthetic timeline row → conditional**

The `MEDEVAC requested` row should only appear when the user actually completed a transmit. Add a parameter to whatever assembles the timeline (likely `HandoffSummary.timeline(for:patient:)` — confirm the signature) and have the caller pass `medevacTransmitted: state.lastMedevacTransmitTime != nil` (introduce a new `AppState` field if absent — set in Task A4's `completeTransmit` when `dest.isFunctional`).

```swift
if medevacTransmitted {
    rows.append(
        .init(
            timestamp: now,
            icon: "antenna.radiowaves.left.and.right",
            kindLabel: "9L",
            detail: "MEDEVAC requested",
            isHot: true
        )
    )
}
```

- [ ] **Step 3: Audit for other static-text "facts"**

```bash
grep -n '"\(class\|hemorrhagic\|shock\|stable\|expectant\|surgical\)' TCCC_IOS/App/HandoffData.swift
```

Each match should be either a label, a header, or removed. Promote anything semantic to engine-derived.

- [ ] **Step 4: Commit**

```bash
git commit -am "fix(safety): remove fabricated 'class III' + unconditional MEDEVAC row"
```

---

## Track B — LLM / clinical correctness

> Track B rebases on Track A's `AppState` changes — start B after A1 lands.

### Task B1: Per-generation session reset

**Why:** `TCCCLanguageModel.swift:46` returns the same `LanguageModelSession` for every `generate()` call. The screens hold generators in `@State` for the screen's lifetime. So the model carries every prior radio script, ZMIST, and narrative as in-context history — and across casualties (because `newPatient()` doesn't reset model sessions). Apple's `LanguageModelSession` is conversational by design; for our four use cases there's no value in carrying context between unrelated generations.

**Files:**
- Modify: `TCCCKit` is not where this lives — `TCCC_IOS/Intelligence/TCCCLanguageModel.swift`

- [ ] **Step 1: Default to fresh session per call**

```swift
actor TCCCLanguageModel {
    private let instructions: String

    init(instructions: String) {
        self.instructions = instructions
    }

    /// Every call gets a fresh session — no context bleeds between casualties
    /// or between generation kinds (radio / ZMIST / narrative / cleanup).
    func generate(prompt: String) async throws -> String {
        let availability = SystemLanguageModel.default.availability
        guard availability == .available else {
            throw ModelError.unavailable(reason: String(describing: availability))
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }
}
```

`reset()` and the cached `session` field are gone — every `generate` is its own conversation.

- [ ] **Step 2: Update callsites**

Search for `.reset()` on a model (`grep -n "model\.reset\|\.reset()" TCCC_IOS/Intelligence/`) and remove — no longer needed.

- [ ] **Step 3: Commit**

```bash
git commit -am "fix(slm): fresh session per generate — no cross-casualty context bleed"
```

---

### Task B2: Wire generators through `TCCCLLMBackend`

**Why:** `TCCCLLMBackend` exists at `TCCC_IOS/Intelligence/TCCCLLMBackend.swift` but the four generators (`RadioScriptGenerator`, `ZMISTNarrativeGenerator`, `EncounterNarrativeGenerator`, `TranscriptCleaner`) all instantiate `TCCCLanguageModel` directly. The Settings backend toggle (`AppState.llmBackend`) exists but does nothing.

**Files:**
- Modify: `TCCC_IOS/Intelligence/TCCCLanguageModel.swift` — make it conform to `TCCCLLMBackend`
- Modify: `TCCC_IOS/Intelligence/AppleFoundationLLMBackend.swift` (verify path) — should already conform; if it just wraps `TCCCLanguageModel`, redirect generators through it instead
- Modify: `TCCC_IOS/Intelligence/RadioScriptGenerator.swift`
- Modify: `TCCC_IOS/Intelligence/ZMISTNarrativeGenerator.swift`
- Modify: `TCCC_IOS/Intelligence/EncounterNarrativeGenerator.swift`
- Modify: `TCCC_IOS/Intelligence/TranscriptCleaner.swift`
- Modify: `TCCC_IOS/App/AppState.swift` — vend a single backend instance via `currentBackend` computed property keyed off `llmBackend`

- [ ] **Step 1: Add `currentBackend` to AppState**

```swift
extension AppState {
    /// The active backend for this AppState's `llmBackend` selection.
    /// Recomputed on each access — cheap because backends are stateless wrappers.
    var currentBackend: any TCCCLLMBackend {
        switch llmBackend {
        case .appleFoundation: AppleFoundationLLMBackend()
        case .lfm2:            LFM2LLMBackend()
        case .qwen3:           QwenLLMBackend()
        }
    }
}
```

- [ ] **Step 2: Refactor each generator to take a backend**

Pattern (apply uniformly):

```swift
struct RadioScriptGenerator {
    static let systemInstructions = """ ... """
    let backend: any TCCCLLMBackend

    init(backend: any TCCCLLMBackend) { self.backend = backend }

    func generate(...) async throws -> String {
        try await backend.generate(
            instructions: Self.systemInstructions,
            prompt: prompt
        )
    }
}
```

- [ ] **Step 3: Update screen `@State` to read backend from AppState**

In every screen that owns a generator, replace `@State private var radioGen = RadioScriptGenerator()` with `@State private var radioGen: RadioScriptGenerator?` and lazy-init in `.task` or `.onAppear` from `state.currentBackend`. (Or pass directly each call — generators are now cheap structs.)

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(slm): inject TCCCLLMBackend into all 4 generators"
```

---

### Task B3: Settings UI for LLM backend toggle

**Why:** The ASR backend (Apple Speech / Parakeet) already has a toggle in Settings. The LLM enum exists but no matching UI. With B2 in place, the toggle now actually swaps engines.

**Files:**
- Modify: `TCCC_IOS/Components/SettingsOverlay.swift` — add an LLM section symmetric to the ASR section

- [ ] **Step 1: Locate ASR toggle for symmetry**

```bash
grep -n "asrBackend\|Apple Speech\|Parakeet" TCCC_IOS/Components/SettingsOverlay.swift
```

- [ ] **Step 2: Add LLM section**

Mirror the ASR section's structure. Show three radio cards (Apple Foundation Models / LFM2 / Qwen 3) with each backend's `BackendAvailability` rendered as a status pill: `READY`, `DOWNLOADING`, `NOT PROVIDED`, `INELIGIBLE`. Disable selection for backends that throw `.notImplemented` (LFM2/Qwen until Track-CLAUDE-md item-7 lands).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(settings): LLM backend picker symmetric to ASR section"
```

---

### Task B4: Port Python validators to TCCCKit

**Why:** `validate_medevac_against_state` (`reports.py:20`) and `validate_zmist_against_state` (`reports.py:584`) cross-check SLM output against the engine and rewrite any line that disagrees. Without them, the SLM can invent triage counts, drop a tourniquet, or change a casualty count and we ship that to the radio. These belong in `TCCCKit` (TCCCReports module) so they're testable without launching the simulator.

**Files:**
- Read: `/Users/ama/TCCC_FEB_2026/src/reports.py` lines 20–600 — both validators plus their helpers (`_calculate_patient_counts`, `_infer_classification`, `_calculate_litter_ambulatory`, `_determine_special_equipment`, `_strip_slm_wrapper`)
- Create: `Packages/TCCCKit/Sources/TCCCReports/MedevacValidator.swift`
- Create: `Packages/TCCCKit/Sources/TCCCReports/ZMISTValidator.swift`
- Create: `Packages/TCCCKit/Tests/TCCCReportsTests/MedevacValidatorTests.swift`
- Create: `Packages/TCCCKit/Tests/TCCCReportsTests/ZMISTValidatorTests.swift`

- [ ] **Step 1: Read and map the Python validators**

```bash
sed -n '20,200p;584,750p' /Users/ama/TCCC_FEB_2026/src/reports.py > /tmp/validators.py
```

Identify every helper. Build a Swift→Python signature table: which `PatientState` field maps to which Python attribute, which regexes match which Swift Regex feature, etc.

- [ ] **Step 2: TDD — write failing tests first**

Pick one round-trip case for each validator (cleanest pick: a single-patient URGENT scenario with one tourniquet). Snapshot the Python output by running:

```bash
cd /Users/ama/TCCC_FEB_2026
python -c "
from src.state import PatientStateEngine
from src.reports import validate_medevac_against_state
# minimal scenario...
"
```

Capture expected output as a `Tests/TCCCReportsTests/Fixtures/medevac_validator_simple.txt` file. Write XCTest:

```swift
final class MedevacValidatorTests: XCTestCase {
    func test_correctsLine5LitterAmbulatoryFromState() throws {
        let engine = PatientStateEngine.standard()
        // ... seed via transcript
        let bogusInput = "Line 5 (# Patients):     A-Litter: 7, B-Ambulatory: 2"
        let validated = MedevacValidator.validate(bogusInput, against: engine)
        XCTAssertTrue(validated.contains("A-Litter: 1"))
        XCTAssertFalse(validated.contains("A-Litter: 7"))
    }
}
```

Run — should FAIL with "no such type MedevacValidator".

- [ ] **Step 3: Implement validators**

Port `validate_medevac_against_state` (lines 20–92) line-by-line. Use `Regex` for the `re.search(r'Line\s*4', ...)` patterns. Helpers (`_calculate_patient_counts`, etc.) become `private static func` on a `MedevacValidator` enum. ZMIST validator port the same way.

- [ ] **Step 4: Run tests**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit
swift test --filter MedevacValidatorTests --filter ZMISTValidatorTests 2>&1 | tail -20
```

Expected: PASS. Plus 697 prior tests still PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(reports): port MEDEVAC + ZMIST validators from Python prototype"
```

---

### Task B5: Apply validators in generators with deterministic fallback

**Why:** B4 only ports the validators — they're not yet wired. Each generator must run its output through the matching validator, and if validation removes/replaces too much (heuristic — define below), fall back to the deterministic `MedevacGenerator` / `ZMISTGenerator` text.

**Files:**
- Modify: `TCCC_IOS/Intelligence/RadioScriptGenerator.swift`
- Modify: `TCCC_IOS/Intelligence/ZMISTNarrativeGenerator.swift`

- [ ] **Step 1: Add validation step + fallback to RadioScriptGenerator**

```swift
func generate(
    from form: NineLineForm,
    patients: [PatientState],
    transcript: String,
    callsign: String = "HAVOC TWO ACTUAL",
    receiver: String = "DUSTOFF SIX"
) async throws -> String {
    let lines = form.entries.map { ... }.joined(separator: "\n")
    let prompt = """ ... """
    let raw = try await backend.generate(instructions: Self.systemInstructions, prompt: prompt)
    let validated = MedevacValidator.validate(raw, against: patients, transcript: transcript)

    // Fallback heuristic: if validator changed > N% of the lines OR the model
    // output is missing a critical Line (1, 3, 5), drop the SLM result and
    // ship deterministic.
    if Self.validationFailed(raw: raw, validated: validated) {
        return MedevacGenerator().generate(form: form).formattedText
    }
    return validated
}

private static func validationFailed(raw: String, validated: String) -> Bool {
    let rawLines = Set(raw.split(separator: "\n").map(String.init))
    let valLines = Set(validated.split(separator: "\n").map(String.init))
    let changed = rawLines.symmetricDifference(valLines).count
    let total = rawLines.count
    return total == 0 || Double(changed) / Double(total) > 0.4
}
```

(Same shape for ZMISTNarrativeGenerator.)

- [ ] **Step 2: Test the fallback path**

Add an XCTest in TCCCReportsTests that constructs a deliberately-wrong SLM output (e.g. claiming 5 urgent patients when state has 1) and asserts the validator produces corrected output. Then add an integration test in the app target — or skip if no app-target test infra exists; document as manual verification.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(slm): validate generator output against state, fall back deterministic on drift"
```

---

## Track C — Audio + concurrency

### Task C1: Fix Parakeet pre-roll ordering

**Why:** `ParakeetTranscriptStream.swift:237–251` drains the ring buffer into the recognizer (lines 238–242) **before** the `AsyncStream` continuation is created (line 245). If the recognizer fires a partial during the drain, there's no continuation yet — the partial is dropped. The audio file already exists at this point so the `.wav` is fine, but the live transcript loses the first ~200ms.

**Files:**
- Modify: `TCCC_IOS/Audio/ParakeetTranscriptStream.swift` (lines 230–260)

- [ ] **Step 1: Reorder — install continuation first**

```swift
let (stream, continuation) = AsyncStream<RecognitionUpdate>.makeStream()
self.continuation = continuation
self.tailDeadline = nil
self.isRecognizing = true
self.currentPartial = ""

// Drain pre-roll AFTER the continuation is wired so any callbacks that fire
// during/after drain land somewhere instead of being dropped.
if let manager {
    for buf in ringBuffer {
        try? await manager.appendAudio(buf)
        try? audioFile?.write(from: buf)
    }
}

return stream
```

- [ ] **Step 2: Verify with build + a smoke test**

```bash
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

(A real-device verification requires the iPhone 17 Pro listed in CLAUDE.md — flagged as manual.)

- [ ] **Step 3: Commit**

```bash
git commit -am "fix(audio): install Parakeet continuation before pre-roll drain"
```

---

### Task C2: Race-safe `AudioGainBox`

**Why:** `AppState.swift:148–151` declares `final class AudioGainBox: @unchecked Sendable { var linear: Float = 1.0 }`. The audio render thread reads this without synchronization while UI writes it from `@MainActor`. Float reads are *probably* atomic on Apple Silicon but the language model has zero obligation to make them so. Use `OSAllocatedUnfairLock` (iOS 16+, available given our 17+ target).

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (lines 140–160 area)

- [ ] **Step 1: Replace with locked primitive**

```swift
import os // OSAllocatedUnfairLock

/// Thread-safe gain holder. UI thread writes, audio render thread reads.
/// A locked Float beats hoping `@unchecked Sendable` is fine.
final class AudioGainBox: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<Float>(initialState: 1.0)
    var linear: Float {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}
```

(Keep `@unchecked Sendable` because the storage handles synchronization but the compiler can't prove it.)

- [ ] **Step 2: Build + run**

`xcodebuild ... build`. Expected: green. If `os` import is missing in AppState, add it.

- [ ] **Step 3: Commit**

```bash
git commit -am "fix(audio): OSAllocatedUnfairLock for AudioGainBox — actual race-safety"
```

---

## Track D — Hit-target compliance

> All three D tasks edit only `Layout.swift` and the directly-affected component files. Single agent, single dispatch.

### Task D1: Raise primary action minimum heights

**Why:** `Layout.bigButtonHeight = 32` violates the 44pt minimum. CLAUDE.md says "minimum 44pt, primary actions 56–64pt".

**Files:**
- Modify: `TCCC_IOS/Design/Layout.swift`
- Modify: `TCCC_IOS/Components/BigButton.swift` (line 40 `.frame(minHeight:)`)

- [ ] **Step 1: Update Layout constants**

```swift
static let minHitTarget: CGFloat = 44
static let bigButtonHeight: CGFloat = 56  // primary action band per design constraint
static let footerHintHeight: CGFloat = 44 // ← new: replaces ad-hoc 30 in FooterHints
static let toggleTabHeight: CGFloat = 44  // ← new: replaces ad-hoc 28 in TCCCCardScreen
```

- [ ] **Step 2: BigButton internal padding sanity-check**

With `minHeight: 56`, the existing `.padding(.vertical, 8)` is fine. No change unless visual review at 56 reveals layout breakage in landscape.

- [ ] **Step 3: Build + visual check**

Run on iPhone 17 Pro simulator. Verify no chrome overflow in landscape, no clipping in 2-row footer layouts.

---

### Task D2: Bring FooterHints to ≥44pt

**Files:**
- Modify: `TCCC_IOS/Chrome/FooterHints.swift` (line 140 area — `actionButton` builder)

- [ ] **Step 1: Update minHeight + minWidth**

```swift
.frame(minWidth: 44, minHeight: Layout.footerHintHeight)
```

If 44pt-tall footer cells exceed the design's chrome budget (review the screenshot in `reference/design_mockup/...`), bump to 44 anyway — the hard constraint wins. Re-tune `padding(.horizontal, 6)` to keep the icon+label layout breathing.

- [ ] **Step 2: Verify in simulator**

Cycle through all 5 screens, confirm footer remains readable + glove-tappable.

---

### Task D3: TCCC Card front/back tabs to ≥44pt

**Files:**
- Modify: `TCCC_IOS/Screens/TCCCCardScreen.swift` (line 80 — `sideTabLabel`)

- [ ] **Step 1: Update minHeight**

```swift
.frame(minHeight: Layout.toggleTabHeight)
```

(Was 28 — promotes to 44.)

- [ ] **Step 2: Commit (combined D1+D2+D3)**

```bash
git commit -am "fix(ui): primary actions 56pt, footer/tabs 44pt — gloved-hand compliance"
```

---

## Track E — Release engineering

### Task E1: Track Package.resolved

**Why:** `.gitignore:19` ignores `Package.resolved`. The build resolved `FluidAudio 0.14.4` from cache while `project.yml:13` only requires `>= 0.9.1`. A clean checkout could resolve any later major version.

**Files:**
- Modify: `/Users/ama/TCCC_IOS/.gitignore`
- Add: `/Users/ama/TCCC_IOS/Packages/TCCCKit/Package.resolved` (and the workspace one if present)

- [ ] **Step 1: Remove the ignore**

In `.gitignore`, delete the `Package.resolved` line.

- [ ] **Step 2: Generate fresh resolved**

```bash
cd /Users/ama/TCCC_IOS/Packages/TCCCKit
swift package resolve
ls *.resolved
```

Repeat for the workspace if `xcodebuild -resolvePackageDependencies` produces a top-level resolved file.

- [ ] **Step 3: Commit**

```bash
git add .gitignore Packages/TCCCKit/Package.resolved
git commit -m "chore(deps): track Package.resolved for reproducible builds"
```

---

### Task E2: Tighten FluidAudio version constraint

**Why:** `from: "0.9.1"` accepts any `>= 0.9.1`. SemVer says minor bumps shouldn't break, but FluidAudio went from 0.9.1 → 0.14.4 (5 minor versions) — this is a young library and the API may move.

**Files:**
- Modify: `/Users/ama/TCCC_IOS/project.yml` (line 13–15)

- [ ] **Step 1: Pin to current resolved**

```yaml
FluidAudio:
    url: https://github.com/FluidInference/FluidAudio.git
    exactVersion: "0.14.4"
```

(Or `upToNextMinor: "0.14.4"` if you prefer to accept patches automatically.)

- [ ] **Step 2: Regenerate Xcode project + verify**

```bash
cd /Users/ama/TCCC_IOS
xcodegen generate
xcodebuild ... build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

- [ ] **Step 3: Commit (combined E1+E2)**

```bash
git commit -am "chore(deps): pin FluidAudio to 0.14.4 exactVersion"
```

---

### Task E3: Minimal CI

**Why:** No CI today. A small GitHub Action that runs `swift test` and the simulator build would catch the most common regressions.

**Files:**
- Create: `/Users/ama/TCCC_IOS/.github/workflows/ci.yml`

- [ ] **Step 1: Workflow**

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request: {}
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.2.app
      - name: Swift Package Tests
        run: swift test --package-path Packages/TCCCKit
      - name: Generate Xcode project
        run: |
          brew install xcodegen
          xcodegen generate
      - name: Simulator build
        run: |
          xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 2: Verify locally that the runner image likely has Xcode 26.2**

(Manual — GitHub may not have Xcode 26.2 available immediately on its `macos-15` image. If unavailable, downgrade to whatever the runner ships and document the version drift.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "chore(ci): swift test + simulator build on push/PR"
```

---

## Track F — Final integration

### Task F1: Full verification + branch finish

- [ ] **Step 1: Tests + build green**

```bash
cd /Users/ama/TCCC_IOS
swift test --package-path Packages/TCCCKit 2>&1 | tail -5
xcodegen generate
xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: 697 + new validator tests pass. Build succeeds.

- [ ] **Step 2: Smoke test on simulator**

Boot iPhone 17 Pro sim, install, walk every screen:
- StatusStrip shows `NO FIX` badge by default.
- Settings → Location source → Demo populates coords + badge changes to `DEMO`.
- Live Capture → speak a scenario → confirm extracted facts appear.
- TCCC Card → switch front/back; tabs are tappable with a glove-sized finger.
- 9-Line → Line 1 says `UNVERIFIED — set location` until source is set.
- Handoff → select ATAK → TRANSMIT → verify `TRANSMIT BLOCKED` log appears (no fake success). Select QR → verify QR overlay appears.
- Settings → tap NEW CAS → verify hold-to-confirm progress bar; release early → no clear.
- Settings → ASR section shows Parakeet/Apple Speech; LLM section shows three backends.

- [ ] **Step 3: Update CLAUDE.md "What's left"**

Mark items as complete (or partially complete) for: GPS state, file protection, validator, backend wiring, hit targets, audio race, ordering bug. Append a one-line summary of this sprint at the bottom of the "Sprint history" section.

- [ ] **Step 4: Run `superpowers:finishing-a-development-branch`**

Decide merge / PR / cleanup path with the user.

---

## Self-review (executed during plan write)

**Spec coverage:** Every numbered review finding except code-organization-refactor (called out as out-of-scope) maps to a task: GPS→A1, file protection→A2, LLM validation→B4+B5, session bleed→B1, backend wiring→B2+B3, hit targets→D1+D2+D3, single-tap destructive→A3, egress destinations→A4, fabricated facts→A5, Parakeet ordering→C1, AudioGainBox→C2, dependency lock→E1+E2.

**Placeholder scan:** No "TBD", "implement later", or "appropriate error handling" left. The two intentional manual-verify steps (Track C real-device, Track F smoke test) are explicitly flagged as such, not silently skipped.

**Type consistency:** `LocationFix` referenced in A1 and A2; `LocationSource` enum cases match across A1's enum, badge call, and SettingsOverlay picker. `TCCCLLMBackend.generate(instructions:prompt:)` signature matches between B2's protocol use and the existing `TCCCLLMBackend.swift` definition (verified). `MedevacValidator.validate(_:against:transcript:)` signature consistent between B4 and B5. `HoldToConfirmButton.holdSeconds` consistent across A3.

---

## Execution Handoff

Two execution options:

**1. Subagent-Driven (recommended for this plan)** — Track A1, C1, C2, the D-tasks-as-one-agent, the E-tasks-as-one-agent, and E3 dispatch in parallel. After A1 lands, B1–B4 dispatch in parallel; B5 sequentially. Track F runs at the end. Two-stage review per task.

**2. Inline Execution** — Walk tasks A1 → A2 → ... → F1 in order in this session. Slower but easier to course-correct mid-flight.
