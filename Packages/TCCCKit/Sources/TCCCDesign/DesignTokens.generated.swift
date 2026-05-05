// DESIGN-TOKENS-GENERATED. Do not hand-edit.
//
// This file is the bake target for the Superplayground design tool.
// It is rewritten in-place by the playground when you bake a chosen
// design. The hand-written `Theme.swift` and `Layout.swift` reference
// values from here when present; if this file is deleted, fallbacks in
// the hand-written files keep the app rendering.
//
// See superplayground.md for the bake contract.

import SwiftUI

public enum DesignTokens {
    /// Whether the playground has baked a custom design over the
    /// hand-written defaults. The `Theme.swift` consumer reads this
    /// via `DesignTokens.hasBaked` to decide which palette to use.
    public static let hasBaked: Bool = false

    public enum Colors {
        // Empty until a bake happens. The committed `Palette.tactical`
        // / `.dark` / `.light` constants are still the source of truth.
    }

    public enum Layout {
        // Empty until a bake happens. The committed `Layout` enum in
        // the app target stays the source of truth.
    }

    /// Per-element baked overrides. Empty until a bake happens. The
    /// committed `.playgroundEditable(_:)` modifier reads this when
    /// the live playground provider is absent (release builds), so
    /// design choices ship even though the editor doesn't.
    public static let bakedOverrides: [String: ElementOverride] = [:]
}
