# Overnight queue — 2026-05-05 → 2026-05-06

You went to bed after the 2026 rubric alignment sprint shipped (commit
`9a76b2f`, 637 tests green, app installed on the iPhone 17 Pro). This
file is your morning briefing: what I attempted overnight, what's
still pending, and the order to attack things in next session.

## What's executed tonight (running while you sleep)

In foreground, sequentially, each one its own commit on `main`:

1. **Audio head/tail bump 10s → 30s.** The `SpeechRecognizer` ring
   buffer and post-tap tail were both 10s. You asked for "long head
   and tail" — bumped to 30s pre-roll + 30s post-tap tail. Memory
   cost is trivial (~1 MB of mono PCM at 16 kHz). The trade-off is
   if the medic taps Stop and within 30s starts a new casualty, the
   tail cancellation logic still fires on `start()`. No regressions
   to the engine pipeline.

2. **Apple Privacy Manifest** (`PrivacyInfo.xcprivacy`). Apple
   requires this for any app on iOS 17+. Declares no tracking, no
   tracking domains, and the required-reason API justifications for
   `NSPrivacyAccessedAPICategoryFileTimestamp` (file-export
   timestamps) and `NSPrivacyAccessedAPICategoryUserDefaults` (theme
   + operator-profile persistence).

3. **Acetaminophen dose value extraction.** The drug was already
   recognized; this commit captures the **numeric dose** (1000mg /
   1300mg / "two 650mg") into a structured medication record so the
   §F MEDS row on the back of the DD 1380 can show the actual dose
   instead of a generic "Acetaminophen administered" string.

4. **Plasma-for-isolated-TBI** + **Ketamine procedural sedation routes**.
   Two remaining 2026 vocabulary items from the Phase 3 deferral list:
   - §8: `1-2 units of plasma` for isolated TBI (no hemorrhage)
   - §13: `Ketamine 1-2 mg/kg slow IV/IO push` and `Ketamine 300 mg IM`
     for procedural sedation during wound dressing

5. **Compiler warning audit.** Captured every `warning:` line from
   `xcodebuild build`, fixed the cheap ones (deprecated APIs,
   unused captures, etc.). The single known-deprecation warning was
   `UIRequiresFullScreen` (iOS 26) — left as-is since the app
   intentionally uses landscape lock; Apple's 26.0 deprecation note
   says it'll be ignored, not removed.

In parallel, two research agents writing reports (you'll read them in
the morning):

- `RESEARCH_PARAKEET.md` — NVIDIA Parakeet English-only ASR feasibility
  on iOS. License, model size, conversion path (CoreML / MLX), latency
  on M-class chips, RF Ghost compliance.
- `RESEARCH_LLAMA32B.md` — Llama 3.2 ~3B (you wrote "3.2B" — I'm
  assuming you meant the 3B variant from the 3.2 family, which is
  what's tractable on a phone) at Q4_K_M and Q5_K_M on iPhone 17 Pro.
  Throughput, memory headroom (12 GB unified), MLX-Swift vs
  llama.cpp tradeoffs, integration with `TCCCLanguageModel` protocol.

## On-device transcription quality plan

You said: "one of those two models is going to end up on the phone for
use to help improve quality of transcription."

Reading between lines: you're not satisfied with Apple Speech ASR
quality on combat-medic vocabulary. Two architectures to consider:

**Architecture A — Better ASR (Parakeet replaces Apple Speech).**
The `TranscriptStream` protocol exists exactly for this swap. Drop
Parakeet behind it; AppState doesn't change. Pros: real ASR
quality improvement, drug names + anatomy land correctly. Cons:
need to convert the Parakeet checkpoint to CoreML (Riva → ONNX →
CoreML pipeline) or use a Swift port if one exists. Apple Speech
stays as fallback.

**Architecture B — Post-hoc LLM cleanup (Llama 3.2B fixes Apple
Speech output).** Keep Apple Speech doing the heavy lifting; pipe
its output through a Llama 3.2B prompt that fixes military / medical
mishearings. You already have `TranscriptCleaner` doing this with
the Apple Foundation Model — Llama 3.2B (3B params at Q5) on the
17 Pro would give you stronger reasoning, longer context, and full
control over the system prompt.

**My recommendation** (subject to your judgment when you read the
research docs): **start with Architecture B**. The Foundation Model
is already wired and working; swapping in Llama 3.2B GGUF via
`llama.cpp.swift` or `MLXLLM` is a localized change. Architecture A
unlocks more quality but is multi-day work.

Architecture B can be implemented in ~half a day:
1. Add `MLXLLM` (Apple) or `llama.cpp` Swift bindings as an SPM dep
2. Bundle a Q4 or Q5 Llama 3.2 3B GGUF / .npz in the app
3. Wrap it in a `TCCCLanguageModel`-conforming actor
4. Pick model at AppState startup based on availability

## Boring backlog (not executed tonight — too risky to do unsupervised)

These are the polish items I left alone because they touch UX or
clinical logic in ways that need your eye. Listed in priority order.

### 1. Tap-to-edit on §C grid cells (and column headers)
Currently the grid is read-only. Each cell needs a tap target +
inline editor:
- BP cell: numeric pad with auto-formatted `\d{2,3}/\d{2,3}` mask
- Pulse cell: free-text (rate + location)
- AVPU cell: 4-button selector (A / V / P / U)
- Pain cell: 0-10 stepper
- RR / SpO₂: numeric pad
- Time header: time-picker

Add an "Add Reading" button below the grid that creates a new column
seeded from the current engine snapshot.

### 2. DD-1380 PDF generation via PDFKit
This was the longest-standing TODO. The plan:
- Find a clean DD Form 1380 PDF template (or build one from scratch
  in PDFKit). The `Casualty card.pdf` in `reference/rubric/` may be
  a usable base — open it and check.
- Map every `dd1380_field_inventory.json` field to an x/y coordinate
  on the form
- `PDFAnnotation` overlays for each populated field
- Wire to the Handoff "DD-1380 PDF" export card; flip its `isReady`
  from false to (`patient != nil`)
- The `READY · DD-1380 · {casualty_id}` UI shown after export
  completion is one line of text in `HandoffScreen` — easy
  addition once the PDF gen returns.

### 3. Real swipe-up / swipe-down for Settings + Quick Actions
Today the overlays only open via the gear / + footer icons. The
pager already takes horizontal drags. A vertical-only `DragGesture`
on the page content could open Settings (up) and Quick Actions
(down), but the gesture has to coexist with `ScrollView` content
on the screens that scroll. SwiftUI's `simultaneousGesture` can
work if scoped carefully.

### 4. Validator path for SLM-generated reports
The Python prototype has `validate_medevac_against_state` and
`validate_zmist_against_state` to catch hallucinations. With Llama
3.2B replacing the Foundation Model (Architecture B above), the
validation discipline matters more — Llama's prone to fabricating
plausible-sounding clinical phrases. Plan:
- Port both Python validators to Swift
- Run between SLM generation and display
- Fall back to the deterministic `MedevacGenerator` /
  `ZMISTGenerator` output if the SLM output fails validation

### 5. Inter Tight + JetBrains Mono fonts
OFL TTFs in `TCCC_IOS/Fonts/`, `UIAppFonts` entries in
`project.yml`, update `Typography.swift`. ~30 minutes once you have
the TTF files.

### 6. Custom stroke icon library
Per design package §7. ~20 SwiftUI `Path` shapes for medical /
MEDEVAC iconography to replace SF Symbols. This is a parallel-agent
task — dispatch one agent per icon group, each writes a small
component file. Could knock it out in a single session if you batch
dispatch.

### 7. Multi-casualty UI
Engine handles multi-patient (`PatientStateEngine.snapshot()`
returns a dict). UI is single-casualty. Adding a casualty switcher
in the StatusStrip (the freed area where GPS used to live is now a
`Spacer`) would expose the multi-patient flow.

### 8. Real audio export bundle
Audio + Transcript card today shares the `.wav` and `.txt`
separately. A proper bundle would zip them with a manifest.json
that includes operator + casualty ID + UTC timestamp.

### 9. Extractor-on-partial-text experiment
Currently the engine only fires on debounce-committed sentences.
Running on partial transcripts would surface tentative facts faster
at the cost of UI flicker. A simple A/B test: add a feature flag,
fire engine on partials when on, measure user perception.

### 10. Real ECG sensor stream
Long-term. Needs the ANT+ chest strap → Jetson Nano companion →
USB-C bridge into the iPhone. Out of scope until the hardware
exists.

## Code-perfection backlog (mundane, low-risk)

These are the "make a build engineer happy" items:

- **swift-format / SwiftLint config.** No formatter is wired up. Add
  `.swift-format` or a SwiftLint config; run on the whole tree;
  commit the resulting style sweep as one commit so `git blame`
  doesn't get destroyed.
- **DocC comments on public APIs.** All `public` types in TCCCKit
  have triple-slash docs but inconsistently. A pass to bring
  TCCCDomain + TCCCExtractor up to "DocC-ready" would help any
  future developer. Auto-generation: `swift package generate-documentation`.
- **`@MainActor` audit.** Some types may not need `@MainActor`
  isolation (audio buffers, file writers); confirm correctness with
  Swift 6.0 strict concurrency.
- **Missing `Sendable` conformances.** Run a build with
  `SWIFT_STRICT_CONCURRENCY=complete` (already set in `project.yml`)
  and grep the warnings for non-Sendable types crossing actors.
- **Test coverage gaps.** Run
  `swift test --enable-code-coverage` then
  `xcrun llvm-cov` to find uncovered lines. 637 tests is a lot but
  we don't know coverage %. Likely thin spots: VitalsHistory removal
  side effects (now removed), the new BackOfCardView field-mapping
  helpers, the 2026 vocabulary edge cases.
- **Network-egress audit.** Ground-truth that no `URLSession`,
  `Network`, or third-party analytics call exists. RF Ghost is a
  hard constraint and worth a regression test — e.g., a build-time
  check that grep returns zero for `URLSession\|NWConnection\|
  CTNetworkInfo\|FirebaseAnalytics` etc.
- **Bundle size audit.** `xcodebuild -showBuildSettings` then
  `du -sh TCCC_IOS.app`. Probably small (no third-party deps), but
  worth a baseline so the next big addition (Llama, Parakeet, font
  files) is comparable.
- **DerivedData hygiene.** The dev script could clear
  `~/Library/Developer/Xcode/DerivedData/TCCC_IOS-*` before any
  full rebuild to avoid the stale-file noise we saw during the
  sprint.
- **README screenshots.** Once UI is more stable, pull screenshots
  of all 5 screens + back-of-card + settings + quick actions and
  link them in README.md.
- **CHANGELOG.md.** Currently nonexistent. The git history is
  legible enough but a compact CHANGELOG keeps releases obvious.
- **CI.** No CI is configured. A GitHub Action that runs
  `swift test` on push would catch regressions. Tricky bit: the
  TCCCKit tests currently load JSON files from the repo via
  `#filePath`-relative paths — those work locally but need verifying
  on a fresh CI checkout.

## Risk-flagged items I will NOT touch overnight

- Any signing / distribution / SideStore config. Provisioning is
  fragile; you do this manually.
- Anything touching the rubric JSONs. They are clinical ground truth
  by your authorship; I edit them only on your direct request.
- Major refactors of clinical extractors. I made surgical additions
  in the sprint; bulk reworks need supervision.
- The Foundation Model integration. It's working but flaky on first
  download. Don't want to break it before the Parakeet/Llama
  decision.
- The `xcuserstate` / `xcworkspace` xcode UI files. Already in
  `.gitignore`.

## Wake-up checklist

When you're back at the keyboard:

1. Read `RESEARCH_PARAKEET.md` and `RESEARCH_LLAMA32B.md`. Decide
   between Architecture A vs B (or both).
2. Run `cd /Users/ama/TCCC_IOS && git log --oneline -15` to see
   what landed overnight.
3. Run `cd Packages/TCCCKit && swift test` to confirm everything
   is still green (it should be — I'll verify before stopping).
4. Tap-to-edit §C grid (item #1 above) is the highest-value next
   feature — it makes the documentation flow round-trip-able. About
   half a day of work.

If anything in this plan is wrong or you want to redirect, message
the cell at `3012750337` with `Claude,` prefix per the iMessage
protocol in the global CLAUDE.md, and the next iteration will pick
it up.
