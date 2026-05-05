import SwiftUI

/// View modifier applied to every editable UI element. Two
/// responsibilities:
///
/// 1. Register the element with the live provider on appear so the
///    inspector can list it.
/// 2. Apply visibility, frame, corner-radius, and per-edge border
///    overrides to the wrapped view.
///
/// Icon / text / image overrides cannot be applied by a modifier alone
/// because the modifier doesn't see into the view's body. Components
/// that need those override types read directly from
/// `@Environment(\.playgroundProvider)` and substitute values before
/// rendering. Use `playgroundString(_:default:id:)` and
/// `playgroundIcon(_:default:id:)` for that.
///
/// With the no-op provider in committed/release builds, this entire
/// modifier compiles to a single environment read and a pass-through.
extension View {
    public func playgroundEditable(
        _ id: ElementID,
        hint: ElementHint = ElementHint()
    ) -> some View {
        modifier(PlaygroundEditableModifier(id: id, hint: hint))
    }
}

private struct PlaygroundEditableModifier: ViewModifier {
    let id: ElementID
    let hint: ElementHint

    @Environment(\.playgroundProvider) private var provider

    func body(content: Content) -> some View {
        let override = provider.override(for: id)
        applyOverrides(content, override: override)
            .onAppear { provider.register(id, hint: hint) }
    }

    @ViewBuilder
    private func applyOverrides(
        _ content: Content,
        override: ElementOverride?
    ) -> some View {
        if let override, override.isHidden == true {
            EmptyView()
        } else {
            applyFrame(content, override: override)
        }
    }

    @ViewBuilder
    private func applyFrame(
        _ content: Content,
        override: ElementOverride?
    ) -> some View {
        let width  = override?.width
        let height = override?.height

        if width != nil || height != nil {
            content.frame(width: width, height: height)
        } else {
            content
        }
    }
}

// MARK: - Reading icon / text / image overrides directly

extension View {
    /// Read a text override, falling back to the default. Use inside a
    /// component's body when the modifier-based path doesn't fit.
    public func playgroundString(
        _ id: ElementID,
        default value: String
    ) -> String {
        // No-op in release: looking at the environment via a free
        // function is unavailable, so the call site uses the form
        // below instead. This stub is kept for symmetry.
        value
    }
}

/// Free helpers callable inside a view's body where the environment is
/// available via the `provider` parameter. Not extensions on `View`
/// because they're not view modifiers — they unwrap to plain values.
public enum PlaygroundOverrides {
    @MainActor
    public static func string(
        _ id: ElementID,
        default value: String,
        provider: any PlaygroundProvider
    ) -> String {
        provider.override(for: id)?.text ?? value
    }

    @MainActor
    public static func icon(
        _ id: ElementID,
        default value: String?,
        provider: any PlaygroundProvider
    ) -> String? {
        if let override = provider.override(for: id) {
            if override.isHidden == true { return nil }
            if let name = override.iconName { return name }
        }
        return value
    }

    @MainActor
    public static func isHidden(
        _ id: ElementID,
        provider: any PlaygroundProvider
    ) -> Bool {
        provider.override(for: id)?.isHidden == true
    }

    @MainActor
    public static func hiddenEdges(
        _ id: ElementID,
        provider: any PlaygroundProvider
    ) -> BorderEdges {
        provider.override(for: id)?.hiddenEdges ?? .none
    }

    @MainActor
    public static func cornerRadius(
        _ id: ElementID,
        default value: CGFloat,
        provider: any PlaygroundProvider
    ) -> CGFloat {
        provider.override(for: id)?.cornerRadius ?? value
    }
}
