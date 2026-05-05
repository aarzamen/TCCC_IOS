# Superplayground — Design Doc

A debug-only, runtime-mutable design playground for the TCCC_IOS app. Three
tabs, one shared override store, all gitignored. Lets the operator (you) edit
icons / headings / images / colors / sizes / per-edge borders live on device,
then bake the chosen design into committed source.

This file is the source of truth for the playground's intentions. If a future
session sees raw color literals re-appearing in components, or sees the
playground hooks deleted from chrome, this doc explains why those patterns
existed and how to restore them.

---

## Why this exists

The five-screen UI is in the "almost good but not quite" zone — close to
right, but the kind of off that hits the eye without naming itself. We need
a way to iterate on tokens (color, corner radii, icons, frame sizes) on
device, not in code, then bake the result back into committed source.

This is a tool. It is not a feature. It must never ship in a release build.

---

## Hard constraints (carry forward)

1. **DEBUG-only, gitignored.** The entire playground module sits under
   gitignored directories. Release builds carry zero playground code.
2. **Hooks are no-ops without the playground.** Every committed component
   carries a `.playgroundEditable(.someID)` modifier. With the playground
   absent, that modifier is a pass-through; with it present, it routes
   through the live override store.
3. **Bake to a separate file.** Chosen designs land in
   `Packages/TCCCKit/Sources/TCCCDesign/DesignTokens.generated.swift`,
   which `Theme.swift` and `Layout.swift` import from. The playground
   never edits hand-written source files.
4. **Concentric corner radii are enforced.** When an outer panel's corner
   radius changes, child rounded elements automatically adopt
   `outer − inset` so the curves stay parallel. This is Apple's HIG rule
   that the eye reads even when the brain doesn't name it.
5. **All `RoundedRectangle` uses `.continuous` (squircle) corners.** Phase 0
   audits and standardizes the existing chrome.
6. **Photo library access is DEBUG-only.** The Info.plist key for photo
   library *add* is already present (used for QR save in production). For the
   playground's photo library *read* (custom image picker), a separate
   `NSPhotoLibraryUsageDescription` key is added under the Debug config only.
   Remove when image-picking work is done.

---

## The three tabs (one playground, three views)

### Tab 1 — Icons / Headings / Title bars / Images

Page-aware editor. Left rail lists every editable element on the current
screen (auto-discovered from the registry). Right inspector for the selected
element:

- **Visibility toggle** (delete = hide; baking emits `.hidden()` or removes
  the element entirely depending on type).
- **Icon picker** — SF Symbols search + recents. "Replace with custom" pulls
  from the photo library (DEBUG only).
- **Text editor** — single line for headings/titles, multi-line for body.
  Live preview updates as you type.
- **Image picker** — same path as icon picker, for full image (not glyph)
  elements.

### Tab 2 — Color (no bloom)

Global, scheme-coherent, never per-element.

- Pick a single anchor color on a wheel.
- Generate complementary / triadic / tetradic / analogous palettes from it.
- Six-role swatch summary:
  - `bg` (deep background)
  - `bg1` (panel surface)
  - `bg2` (header strip surface)
  - `fg` (primary text)
  - `fg1` (secondary text)
  - `accent` (the live-record red equivalent)
- Saturation + Brightness sliders re-derive the whole palette to keep the
  scheme coherent — no per-color sliders.
- "Bake" writes a new `Palette` constant into `DesignTokens.generated.swift`.
- **No bloom.** Removed from spec. Lightweight aesthetic that doesn't fit
  this app.

### Tab 3 — Granular sizing & per-edge frame deletion

Selected element gets:

- **Width / height sliders** with live preview.
- **Corner-radius slider.** Concentric child radii follow automatically.
- **Frame visibility toggle** (delete the whole element).
- **Per-edge border toggles** — top / bottom / leading / trailing. The
  existing `Panel` strokes a `Rectangle` (all four edges or none). Phase 0
  introduces a `SidedBorder` shape that draws each edge as an independent
  path; `Panel` switches to it when any edge override is non-default and
  remains visually identical when no overrides are set.
- **Drag handles** on the selected element's corners and edges (polish item;
  sliders are sufficient v1).

---

## Architecture

### Directory layout

Committed:

```
Packages/TCCCKit/Sources/TCCCDesign/
├── Playground/
│   ├── ElementID.swift                # Stable IDs for editable elements
│   ├── ElementOverride.swift          # Override value types
│   ├── PlaygroundProvider.swift       # Protocol + environment + no-op default
│   ├── PlaygroundEditableModifier.swift  # The `.playgroundEditable(_:)` hook
│   └── PlaygroundEntryRegistry.swift  # Runtime registry for the live module
├── Concentric.swift                   # Concentric-radius helper + .continuous
└── DesignTokens.generated.swift       # Bake target
```

Gitignored:

```
TCCC_IOS/_Playground/
├── PlaygroundBoot.swift               # Hooks LivePlaygroundProvider into the registry
├── LivePlaygroundProvider.swift       # @Observable override store + JSON persist
├── PlaygroundRoot.swift               # Three-tab host view
├── EntryGesture.swift                 # 4-finger long-press to open
├── PresetIO.swift                     # Save / load / export presets
├── Bake/
│   └── TokenBaker.swift               # Writes DesignTokens.generated.swift
├── Common/                            # Shared inspector chrome
├── IconsTab/                          # Tab 1 source (agent A)
├── ColorTab/                          # Tab 2 source (agent B)
└── SizingTab/                         # Tab 3 source (agent C)
```

### How the gitignored module attaches to committed code

The committed code never references types defined only in `_Playground/`.
Wiring uses a runtime registry pattern:

1. `PlaygroundEntryRegistry` (committed) holds two `@MainActor` static
   optionals: a root-view factory and a provider factory.
2. The `_Playground/PlaygroundBoot.swift` file (gitignored) populates those
   factories.
3. Boot is triggered by the app's `init()` under a `#if PLAYGROUND_ENABLED`
   gate, calling a function that lives in `_Playground/`. When the flag is
   off, the call site compiles to nothing and the gitignored files are not
   referenced.

### Enabling / disabling

`PLAYGROUND_ENABLED` is a Swift compilation condition.

- **To enable**: set `PLAYGROUND_ENABLED` in the Debug config of
  `project.yml` (a one-line uncomment), make sure `_Playground/` is restored
  on disk, run `xcodegen generate`.
- **To disable**: unset the flag. Committed code is unconditional no-op;
  builds succeed whether or not `_Playground/` exists on disk.
- **Release builds**: never set the flag. The gitignored directory and the
  flag are independent — both must be present for the playground to
  activate.

### Why not a separate SPM module?

Because `Package.swift` is committed. Declaring a target whose source
directory is gitignored breaks `swift build` on clean clones. The
runtime-registry pattern dodges this entirely: committed code declares the
hooks, gitignored code populates them, the compilation flag closes the loop.

---

## Override flow

```
┌─────────────────────────┐    @Environment(\.playgroundProvider)
│ Component                │ ─────────────────────────┐
│   .playgroundEditable    │                          ▼
│       (.transcriptTitle)│            ┌──────────────────────────┐
└─────────────────────────┘            │ PlaygroundProvider       │
                                       │  (no-op default)         │
                                       │                          │
                                       │  override(for:) -> nil   │
                                       └──────────────────────────┘
                                                   │
                            (when playground booted, environment is
                             replaced with LivePlaygroundProvider)
                                                   │
                                                   ▼
                                       ┌──────────────────────────┐
                                       │ LivePlaygroundProvider    │
                                       │  reads from JSON-backed  │
                                       │  override map            │
                                       └──────────────────────────┘
```

The `.playgroundEditable(_:)` modifier:

1. Registers the element ID with the live provider on appear (so the
   inspector knows the element exists on the current screen).
2. Reads the override for its ID; applies hide / frame override / per-edge
   overrides to the underlying view.
3. With the no-op provider: registration is a no-op, override lookup is
   nil, view is unchanged.

Icon / text / image overrides cannot be applied by a modifier alone (the
modifier doesn't see into the view's body). For those, the affected
component reads the override directly via `@Environment(\.playgroundProvider)`
and substitutes the value before rendering. Phase 0 wires this for `Panel`,
`PageHeader`, `BigVital`, and `SmallVital`. Other components opt in as
needed.

---

## Bake-to-source contract

`DesignTokens.generated.swift` is the only file the playground writes back
to. Its public surface:

```swift
public enum DesignTokens {
    public enum Color {
        public static let bg: SwiftUI.Color = ...
        public static let bg1: SwiftUI.Color = ...
        ...
    }

    public enum Layout {
        public static let panelCornerRadius: CGFloat = ...
        public static let panelPadding: CGFloat = ...
        ...
    }
}
```

`Theme.swift` and `Layout.swift` reference `DesignTokens.*` by default. When
the playground bakes, it rewrites the generated file in-place. The hand-
written files never change. If the generated file is deleted, fallback
constants in `Theme.swift` / `Layout.swift` keep the app rendering with the
last hand-written defaults.

The playground also bakes per-element overrides (hidden state, per-edge
border state, custom icons) by emitting a `DesignTokens.Overrides` map that
the committed `.playgroundEditable(_:)` modifier reads via a separate,
always-present `BakedOverridesProvider` (not the live one). Baked overrides
ship in release builds; the editor that produced them does not.

---

## Known follow-ups

- **Color tab's "APPLY (live)" button** sets `LivePlaygroundProvider.paletteOverride`
  but committed code does not yet read that field back into the SwiftUI
  `\.palette` environment. The BAKE button works end-to-end (writes to
  `DesignTokens.generated.swift`); APPLY is a no-op at the chrome layer
  until live wiring lands. Two options when you're ready:
  1. Have `AppState` observe the provider and recompute `theme.palette`,
     OR
  2. Add a small `_Playground/PaletteEnvironmentBridge.swift` modifier
     that the gitignored boot inserts above `.playgroundOverlay()`.
  Option 2 keeps the dep direction clean.

## Notes for future-you / future-Claude

- **Hooks should never disappear.** If you find yourself removing a
  `.playgroundEditable(.id)` from a component, ask why. The hook is free at
  runtime and its presence is what lets the playground discover the element.
- **Don't add raw colors to components.** Always go through `palette.*` or
  `DesignTokens.Color.*`. Raw hex literals in component files are the
  pattern that this whole playground exists to prevent.
- **Concentric radii.** When wrapping a rounded element in another rounded
  element, use the `Concentric` helpers in `TCCCDesign/Concentric.swift`.
  Don't hardcode inner radii.
- **Photo library entitlement.** The `NSPhotoLibraryUsageDescription` key
  added under Debug config exists only for the playground's image picker.
  Remove it from `project.yml` when image-picking work is done — the
  production `NSPhotoLibraryAddUsageDescription` for QR save is separate
  and stays.
- **No bloom.** Don't re-add it without a deliberate reason. The original
  spec called for it; we removed it because it doesn't fit this app's
  visual language. If the question comes up again, the answer is still no.

---

## Sequencing

Phase 0 (foundation, chrome hooks, gitignore, project.yml gating) is built
sequentially in the main session. Phases 1 / 2 / 3 (tab implementations) are
built by three parallel sub-agents writing into disjoint subdirectories of
`_Playground/`.

After bake-to-source is verified end-to-end on at least one design change,
the playground is considered complete. Iterate on design via the playground;
commit only the resulting `DesignTokens.generated.swift` deltas.

---

Last updated: 2026-05-05.
