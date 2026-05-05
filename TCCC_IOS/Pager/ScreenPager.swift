import SwiftUI

struct ScreenPager: View {
    let state: AppState
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(AppState.Screen.allCases) { screen in
                    screenView(for: screen)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .offset(x: -CGFloat(state.screen.rawValue) * geo.size.width + dragOffset)
            .animation(.pageTransition, value: state.screen)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let proposed = value.translation.width
                        let resistance: CGFloat = 0.4
                        if (state.screen == .liveCapture && proposed > 0) ||
                           (state.screen == .handoff && proposed < 0) {
                            dragOffset = proposed * resistance
                        } else {
                            dragOffset = proposed
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        let threshold = Layout.swipeThreshold
                        let priorScreen = state.screen
                        withAnimation(.pageTransition) {
                            dragOffset = 0
                            if dx + velocity * 0.3 < -threshold {
                                state.nextScreen()
                            } else if dx + velocity * 0.3 > threshold {
                                state.previousScreen()
                            }
                        }
                        // Light tactile confirmation that the swipe
                        // committed to a new page. Gated on an actual
                        // screen change so resistance-edge bounce-backs
                        // (first / last screen) stay silent.
                        if state.screen != priorScreen {
                            Haptics.tap(.light)
                        }
                    }
            )
        }
        .clipped()
    }

    @ViewBuilder
    private func screenView(for screen: AppState.Screen) -> some View {
        switch screen {
        case .liveCapture: LiveCaptureScreen(state: state)
        case .vitals:      VitalsScreen(state: state)
        case .tcccCard:    TCCCCardScreen(state: state)
        case .medevac:     MedevacScreen(state: state)
        case .handoff:     HandoffScreen(state: state)
        }
    }
}
