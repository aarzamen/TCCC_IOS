import SwiftUI

// PLAYGROUND HOOK — see superplayground.md.
// The PLAYGROUND_ENABLED compilation condition is set in project.yml's
// Debug config (commented out by default). Enabling it requires the
// gitignored _Playground/ directory to be present on disk.

@main
struct TCCC_IOSApp: App {
    @State private var state = AppState()

    init() {
        #if PLAYGROUND_ENABLED
        // Defined in _Playground/PlaygroundBoot.swift (gitignored).
        // Populates PlaygroundEntryRegistry so .playgroundOverlay()
        // attaches the editor at runtime.
        PlaygroundBoot.activate()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
    }
}
