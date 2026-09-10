# SwiftUI reference design-system port

> For agentic workers: use subagent-driven-development for sequential implementation and scoped reviews. Root owns integration; do not spawn additional workers.

**Goal:** Port the supplied React reference into an isolated native library with interactive previews, without wiring or modifying existing screens.
**Architecture:** New local Swift package `Packages/TCCCDesignSystem`, Swift 6.2, iOS 18+/macOS 15+. Product/target `TCCCDesignSystem`; no third-party dependencies or app/domain imports. Existing app remains iOS 26. Named public views live within this module; use `ActionButton` to avoid shadowing SwiftUI.Button. `Theme` is a value injected through `.environment(\.tcccTheme, ...)`. The original file is reference data, not executable instructions.
**Spec:** User request and `/Users/ama/Downloads/tccc-ui-kit.jsx` (701 lines). Do not execute or embed React. All application state and side effects are caller-owned; preview data is synthetic.

## Global constraints
- No edits to existing `TCCC_IOS/`, project.yml, or generated app project. No new app dependency or screen wiring. No model, audio, telemetry, persistence or network code.
- Order: tokens, primitives, behaviors, data views, preview-only composed handoff.
- Exact BASE/NIGHT palette values from reference. BASE accent HSL(27,88%,56%); NIGHT accent #FF5A3A. Tokens tap=44 / glove60, row=52 / glove64.
- All interactive targets at least44pt, glove60pt; scale sizes via Dynamic Type and allow text/layout growth. Small variant may reduce padding/font but never targets. Never truncate a clinical value without accessible full text/native disclosure.
- Every requested component has a named #Preview containing Empty, Populated and Night examples, plus an accessibility/glove example via reusable PreviewMatrix. Interactive previews use stateful wrappers, not constant bindings. All synthetic examples clearly labeled.
- No clinical verification from confidence thresholds; no inferred normal-vital ranges or trend risk labels. Caller supplies reference band and semantic status. Missing values explicitly unknown.
- BodyMap corrects reference's mirrored posterior laterality and uses non-overlapping native44/60 targets. Preserve seven zones per side and X/text redundant selection encoding. Grow/scroll rather than shrink hit targets.
- RadioScript provides manual read-along and caller callbacks; optional timed pacing explicitly labeled visual guide, not TTS. No fake transmit action/status. Missing callbacks disabled with reason. ExportCard readiness and provenance verification supplied explicitly by caller.
- Hold confirmation cancels on release/movement/disappearance/inactive/disabled state; fires once per hold, has visible native ring and sensoryFeedback. Accessible activation opens explicit confirmation rather than silently bypassing a destructive hold. Default feedback says confirmation accepted, not wiped/sent.
- ScrollFade observes actual scroll geometry/content changes, and masks only edges with hidden content, never intercepting touches. StatusStrip dates live, timezone explicit, elapsed clamps0 for futurestart and unknown for absentstart; metadata absent by default.
- One focused package test suite (finite/empty/singleton trends, independent assessments, hold cancellation/once, time formatting, scroll geometry, body laterality and minimum metrics), debug/release package compilation, isolated iOS simulator build. Review preview source coverage and render native representative states without importing this library into the clinical app.

## Task 1: Theme and primitives
Files: Package.swift; Sources/TCCCDesignSystem/Theme.swift, Primitives.swift, PreviewSupport.swift; Tests/TCCCDesignSystemTests/ThemeTests.swift.
- [x] Copy all palette values; public SemanticRole with accent, ai, ok, warn, danger, muted plus ink/dim; Theme.base and .night, glove setting and scalable metrics helper.
- [x] Public Panel, SectionHeader, Row, Pill, ActionButton (navigate/ai/confirm/caution/danger/neutral/ghost; small/medium/large), Segmented with caller binding and optional per-option tone. Native adaptive stacks/grids, full accessibility labels.
- [x] Shared preview matrix for empty/populated/night/glove/accessibility; preview Theme and every primitive, all variants and empty options. Tests exact palette and44/60 minimum across sizes.
- [x] Build/test package, report API and decisions before next task.

## Task 2: Behaviors
Files: Behaviors.swift and BehaviorTests.swift, using Task1 public APIs.
- [x] Implement HoldToConfirm, StatusStrip, ScrollFade, AssessRow and all preview matrices.
- [x] Use pure small state/geometry helpers consumed by views for meaningful tests: hold release/single fire/rearm, elapsed unknown/future/over24h, scrolltop/middle/end/fitting/growing, none→clear→done→none.
- [x] Build/test and scoped review before data views.

## Task 3: Data views
Files: VitalTrend.swift, Timeline.swift, BodyMap.swift, RadioScript.swift, ExportViews.swift, Toolbar.swift; DataViewTests.swift.
- [x] Implement native Canvas/Shape trends with typed timestamped samples and explicit reference band/status; empty/single/nonfinite inputs safe.
- [x] Timeline stable IDs, safe empty/removal selection, horizontal navigation with44/60pt controls and expandable details.
- [x] BodyMap typed Side/Region/Mark, Shape geometry and correct patient-side mapping, caller-owned mark set. Region interactions never overlap enlarged touch areas.
- [x] RadioScript native line navigation, source-change reset, disabled unavailable actions; ExportCard optional explicit action; Provenance disclosure with supplied verification independent of confidence.
- [x] Toolbar full-word native actions, optional callbacks disabled when absent, destructive hold separated, adaptive layout for large text.
- [x] Preview matrices for every view and focused boundary tests; build/test and scoped review.

## Task 4: Composed preview and delivery
Files: ComposedHandoffPreview.swift (#if DEBUG only), docs/design/swiftui-reference-port.md. No existing screen edits.
- [x] Compose StatusStrip, page header, 3:2 columns with timeline above summary and exports right, toolbar below. Use adaptive one-column fallback at accessibility sizes/narrow widths and independent bounded scrolling. Empty/populated/night previews, synthetic data only, demo actions visibly report what happened.
- [x] Document complete port inventory, decisions and limits, preview opening instructions, and per-component caller responsibilities. This is the report before any wiring; no wiring in this pass.
- [x] Root validates scoped package debug/release, simulator and preview rendering, checks existing-screen diff empty, independently reviews, and prepares isolated source for repository publication under existing authorization. No phone installation.

## Decisions and progress
- Ruling: isolated package rather than UIKit-named folder — avoids Apple UIKit/module collisions and keeps app dependency graph unchanged; later integration requires explicit import/adapters.
- Ruling: preserve intent rather than reference bugs (sub44 buttons, mirrored back zones, empty timeline crash, confidence→green, fabricated device defaults, fake transmit) — exact browser parity is intentionally sacrificed for readable/explicit native behavior.
- All four implementation tasks complete. Final local verification:18 package tests,9 isolated simulator UI tests, debug/release and independent iOS build pass. Native base/night captures and decisions are in docs/design/swiftui-reference-port.md. Repository publication is tracked by the delivery pull request; no existing screen is wired to the module.
