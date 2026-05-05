import SwiftUI

/// Concentric corner-radius helpers and squircle (`.continuous`) defaults.
///
/// When a rounded rect sits inside another with inset `p`, the inner
/// corner radius must equal `outer − p` for the curves to remain
/// parallel. Apple's HIG calls this concentric corners; the eye reads
/// the violation even when the brain doesn't name it.
///
/// Use `Concentric.inner(of:inset:)` whenever you nest a rounded element
/// inside a `Panel` or any other rounded surface. Don't hardcode the
/// inner radius.
public enum Concentric {
    /// The radius a child rounded element should use when nested inside
    /// a parent of the given outer radius with `inset` padding on all
    /// sides. Floored at 0; never returns negative.
    public static func inner(of outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }

    /// The standard rounded-rect style for the entire app. Always
    /// `.continuous` (squircle) — `.circular` reads as cheap.
    public static let style: RoundedCornerStyle = .continuous
}

extension RoundedRectangle {
    /// `RoundedRectangle(cornerRadius:)` with the app-standard `.continuous`
    /// style baked in. Use this in place of the default initializer
    /// everywhere; `Concentric.style` is the single source of truth for
    /// corner shape.
    public static func tccc(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: Concentric.style)
    }
}

/// Environment value carrying the parent rounded surface's outer radius
/// (and the inset between parent and child). Children that want
/// concentric corners read this and call `Concentric.inner(of:inset:)`.
///
/// Default is `.zero` for both, meaning "no parent rounded surface" — a
/// child rendered at the root takes whatever radius it likes.
public struct ConcentricContext: Equatable, Sendable {
    public let outerRadius: CGFloat
    public let inset: CGFloat

    public static let none = ConcentricContext(outerRadius: 0, inset: 0)

    public init(outerRadius: CGFloat, inset: CGFloat) {
        self.outerRadius = outerRadius
        self.inset = inset
    }

    public var innerRadius: CGFloat {
        Concentric.inner(of: outerRadius, inset: inset)
    }
}

private struct ConcentricContextKey: EnvironmentKey {
    static let defaultValue: ConcentricContext = .none
}

extension EnvironmentValues {
    public var concentric: ConcentricContext {
        get { self[ConcentricContextKey.self] }
        set { self[ConcentricContextKey.self] = newValue }
    }
}

extension View {
    /// Mark this view as a rounded surface so child views can derive
    /// their own corner radius concentrically. Set on every panel /
    /// card / surface that has a corner radius.
    public func concentricSurface(
        radius: CGFloat,
        inset: CGFloat
    ) -> some View {
        environment(\.concentric, ConcentricContext(outerRadius: radius, inset: inset))
    }
}
