import SwiftUI

struct SenderPlaybackView: View {
    let onBack: () -> Void

    @State private var viewModel = SenderViewModel()
    @State private var page: SenderPage = .compose
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                SenderComposeView(
                    viewModel: viewModel,
                    onBack: onBack,
                    onSend: {
                        withAnimation(.pageTransition) {
                            page = .readout
                        }
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)

                SenderReadoutView(
                    viewModel: viewModel,
                    onReedit: {
                        withAnimation(.pageTransition) {
                            page = .compose
                        }
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -CGFloat(page.rawValue) * geo.size.width + dragOffset)
            .animation(.pageTransition, value: page)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        withAnimation(.pageTransition) {
                            dragOffset = 0
                            if dx < -Layout.swipeThreshold {
                                page = .readout
                            } else if dx > Layout.swipeThreshold {
                                page = .compose
                            }
                        }
                    }
            )
        }
        .clipped()
    }
}

private enum SenderPage: Int {
    case compose = 0
    case readout = 1
}
