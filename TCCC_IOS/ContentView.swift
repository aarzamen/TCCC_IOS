import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.
// `.playgroundOverlay()` wraps the root with the design playground's
// entry gesture and inspector overlay when the playground is booted.
// Compiles to a pass-through when it is not (release builds, clean
// clones).

struct ContentView: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StatusStrip(state: state)
                ScreenPager(state: state)
                    .frame(maxHeight: .infinity)
            }

            if state.settingsOpen {
                SettingsOverlay(state: state)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if state.quickActionsOpen {
                QuickActionsSheet(state: state)
                    .transition(.opacity)
                    .zIndex(2)
            }

            // Confirmation banner sits at z=3 so it floats above everything
            // else — including the Settings overlay if a wipe is requested
            // while Settings is open.
            ConfirmationBanner(state: state)
                .zIndex(3)
        }
        .preferredColorScheme(state.theme.preferredColorScheme)
        .environment(\.palette, state.theme.palette)
        .ignoresSafeArea(.keyboard)
        .animation(.fast, value: state.settingsOpen)
        .animation(.fast, value: state.quickActionsOpen)
        .animation(.fast, value: state.pendingConfirmation?.id)
        .playgroundOverlay()
    }
}

#Preview {
    ContentView(state: AppState())
}
