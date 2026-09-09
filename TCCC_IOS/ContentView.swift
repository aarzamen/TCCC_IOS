import SwiftUI

struct ContentView: View {
    let state: AppState
    @State private var rootRoute: RootRoute = .splash

    var body: some View {
        Group {
            switch rootRoute {
            case .splash:
                SplashView(
                    onOpenMain: { rootRoute = .main },
                    onOpenDevTools: { rootRoute = .devTools },
                    onOpenLab: { rootRoute = .lab }
                )
            case .main:
                MainAppShell(state: state, onReturnToSplash: { rootRoute = .splash })
            case .lab:
                YapLabView(state: state, onBack: { rootRoute = .splash })
            case .devTools:
                DevToolsRootView(state: state, onReturnToSplash: { rootRoute = .splash })
            }
        }
        .preferredColorScheme(state.theme.preferredColorScheme)
        .environment(\.palette, state.theme.palette)
    }

    private enum RootRoute {
        case splash
        case main
        case devTools
        case lab
    }
}

private struct MainAppShell: View {
    let state: AppState
    let onReturnToSplash: () -> Void
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
                SettingsOverlay(state: state, onReturnToSplash: onReturnToSplash)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if state.quickActionsOpen {
                QuickActionsSheet(state: state)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if state.reviewOpen {
                GraniteReviewOverlay(state: state)
                    .transition(.opacity)
                    .zIndex(2)
            }

            // Confirmation banner sits at z=3 so it floats above everything
            // else — including the Settings overlay if a wipe is requested
            // while Settings is open.
            ConfirmationBanner(state: state)
                .zIndex(3)

            // Voice-command auto-fire banner (Task S3-7). Same z-band as
            // ConfirmationBanner — `armVoiceCommand` and
            // `requestConfirmation` are mutually exclusive in practice, but
            // the layout doesn't depend on that.
            VoiceCommandBanner(state: state)
                .zIndex(3)
        }
        .sheet(item: Binding(get: { state.clinicalEntrySheet }, set: { state.clinicalEntrySheet = $0 })) { kind in
            ClinicalEntrySheet(state: state, kind: kind)
        }
        .ignoresSafeArea(.keyboard)
        .animation(.fast, value: state.settingsOpen)
        .animation(.fast, value: state.quickActionsOpen)
        .animation(.fast, value: state.reviewOpen)
        .animation(.fast, value: state.pendingConfirmation?.id)
        .animation(.fast, value: state.pendingVoiceCommand?.command)
    }
}

#Preview {
    ContentView(state: AppState())
}
