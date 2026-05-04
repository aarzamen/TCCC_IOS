import SwiftUI

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
        }
        .preferredColorScheme(state.theme.preferredColorScheme)
        .environment(\.palette, state.theme.palette)
        .ignoresSafeArea(.keyboard)
        .animation(.fast, value: state.settingsOpen)
        .animation(.fast, value: state.quickActionsOpen)
    }
}

#Preview {
    ContentView(state: AppState())
}
