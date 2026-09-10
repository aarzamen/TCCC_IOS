import SwiftUI

struct SenderPlaybackView: View {
    let onBack: () -> Void

    @State private var viewModel = SenderViewModel()
    @State private var ambientMeter = AmbientMeter()
    @State private var page: SenderPage = .compose
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch page {
                    case .compose:
                        SenderComposeView(
                            viewModel: viewModel,
                            ambientMeter: ambientMeter,
                            onBack: {
                                endSurfaceActivity()
                                onBack()
                            },
                            onSend: { show(.readout) }
                        )
                    case .readout:
                        SenderReadoutView(
                            viewModel: viewModel,
                            onReedit: { show(.compose) }
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        // Page changes use Send / Play and Re-edit. A page-wide drag competes
        // with the sliders and can leave Compose while the user adjusts them.
        .onDisappear { endSurfaceActivity() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { endSurfaceActivity() }
        }
    }

    private func show(_ destination: SenderPage) {
        guard destination != page else { return }
        endSurfaceActivity()
        withAnimation(.pageTransition) { page = destination }
    }

    private func endSurfaceActivity() {
        viewModel.endSurfaceActivity(stopAmbient: ambientMeter.stop)
    }
}

private enum SenderPage: Int {
    case compose = 0
    case readout = 1
}
