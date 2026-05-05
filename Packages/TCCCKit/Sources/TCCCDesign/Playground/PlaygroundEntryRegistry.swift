import SwiftUI

/// Runtime registry that lets the gitignored `_Playground/` module
/// attach itself to committed code without committed code referencing
/// any gitignored type.
///
/// The flow:
///
/// 1. Committed `TCCC_IOSApp.init()` calls `PlaygroundEntryRegistry`
///    accessors. They return nil by default.
/// 2. When the playground is enabled (`#if PLAYGROUND_ENABLED`) the
///    gitignored `PlaygroundBoot.activate()` populates the static
///    factories on this registry.
/// 3. Committed `ContentView` renders `.playgroundOverlay()` which
///    reads the registry and either shows the playground entry gesture
///    + overlay or compiles to a pass-through.
///
/// Why this pattern? `Package.swift` and committed Xcode sources can't
/// reference symbols defined only in a gitignored directory. The
/// runtime registry decouples the two so committed code stays
/// referentially closed.
@MainActor
public enum PlaygroundEntryRegistry {
    /// Factory producing the playground's root view (the three-tab
    /// host). Set by `PlaygroundBoot.activate()` when present. `nil`
    /// in committed-only / release builds.
    public static var rootViewFactory: (() -> AnyView)?

    /// Factory producing the live override provider. The same
    /// instance is injected into the SwiftUI environment so
    /// `.playgroundEditable(_:)` modifiers route through it.
    public static var providerFactory: (() -> any PlaygroundProvider)?

    /// Reset all registrations. Used in tests; you should never need
    /// this at runtime.
    public static func reset() {
        rootViewFactory = nil
        providerFactory = nil
    }

    /// Whether a playground backend is registered.
    public static var isAvailable: Bool {
        rootViewFactory != nil && providerFactory != nil
    }
}

extension View {
    /// Wraps the receiver with the playground entry gesture and
    /// overlay if a playground backend is registered. Pass-through
    /// otherwise.
    ///
    /// Apply once at the root of `ContentView`.
    public func playgroundOverlay() -> some View {
        modifier(PlaygroundOverlayModifier())
    }
}

private struct PlaygroundOverlayModifier: ViewModifier {
    @State private var provider: (any PlaygroundProvider)?
    @State private var isPresented: Bool = false

    func body(content: Content) -> some View {
        Group {
            if let provider, let factory = PlaygroundEntryRegistry.rootViewFactory {
                content
                    .environment(\.playgroundProvider, provider)
                    // Four-finger long-press = open. Won't fire under
                    // a glove and is not a gesture the medic UI uses
                    // for anything else.
                    .gesture(
                        LongPressGesture(minimumDuration: 0.6)
                            .simultaneously(
                                with: SpatialTapGesture(count: 1)
                            )
                            .onEnded { _ in
                                isPresented = true
                            },
                        including: isPresented ? .subviews : .all
                    )
                    .overlay {
                        if isPresented {
                            factory()
                                .transition(.opacity)
                                .zIndex(100)
                                .onTapGesture {
                                    // Tap on the playground's scrim
                                    // dismisses; the playground itself
                                    // intercepts taps inside content.
                                }
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: isPresented)
            } else {
                content
            }
        }
        .task {
            if let factory = PlaygroundEntryRegistry.providerFactory, provider == nil {
                provider = factory()
            }
        }
    }
}
