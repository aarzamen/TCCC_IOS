import SwiftUI

/// The contract every playground backend implements. Components read
/// from this via `@Environment(\.playgroundProvider)`.
///
/// Two implementations exist:
///
/// 1. `NoopPlaygroundProvider` — committed, default. Returns `nil` for
///    every override and ignores registrations. Compiles into release
///    builds; costs nothing at runtime.
/// 2. `LivePlaygroundProvider` — gitignored, lives in `_Playground/`.
///    Backed by an `@Observable` JSON-persisted store. Wired up only
///    when the playground is booted.
@MainActor
public protocol PlaygroundProvider: AnyObject {
    /// Inform the provider that this element exists on screen. The
    /// inspector uses this to populate its left rail per current
    /// screen. Idempotent; safe to call on every appear.
    func register(_ id: ElementID, hint: ElementHint)

    /// Read the current override for an ID. `nil` means "no edits";
    /// component renders defaults.
    func override(for id: ElementID) -> ElementOverride?

    /// Whether the playground UI is currently presented. Components
    /// can use this to render selection indicators or hit overlays.
    var isPresenting: Bool { get }

    /// The ID of the element the user has selected in the inspector,
    /// if any. Used to draw selection handles.
    var selectedID: ElementID? { get }
}

/// Lightweight metadata the component passes when registering. Helps
/// the inspector show a sensible label next to each ID.
public struct ElementHint: Equatable, Sendable {
    public var label: String?
    public var supports: Capabilities

    public struct Capabilities: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let visibility   = Capabilities(rawValue: 1 << 0)
        public static let icon         = Capabilities(rawValue: 1 << 1)
        public static let text         = Capabilities(rawValue: 1 << 2)
        public static let image        = Capabilities(rawValue: 1 << 3)
        public static let frame        = Capabilities(rawValue: 1 << 4)
        public static let cornerRadius = Capabilities(rawValue: 1 << 5)
        public static let edges        = Capabilities(rawValue: 1 << 6)
    }

    public init(label: String? = nil, supports: Capabilities = []) {
        self.label = label
        self.supports = supports
    }
}

/// Default provider used in committed code and release builds. Reads
/// from `DesignTokens.bakedOverrides` so design choices baked by the
/// playground take effect in release builds even though the editor is
/// gone. Registration is a no-op (no inspector to populate).
@MainActor
public final class BakedPlaygroundProvider: PlaygroundProvider {
    public static let shared = BakedPlaygroundProvider()

    public init() {}

    public func register(_ id: ElementID, hint: ElementHint) {}

    public func override(for id: ElementID) -> ElementOverride? {
        DesignTokens.bakedOverrides[id.description]
    }

    public var isPresenting: Bool { false }
    public var selectedID: ElementID? { nil }
}

private struct PlaygroundProviderKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: any PlaygroundProvider = BakedPlaygroundProvider.shared
}

extension EnvironmentValues {
    public var playgroundProvider: any PlaygroundProvider {
        get { self[PlaygroundProviderKey.self] }
        set { self[PlaygroundProviderKey.self] = newValue }
    }
}
