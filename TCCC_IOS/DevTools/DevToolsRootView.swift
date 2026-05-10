import SwiftUI

struct DevToolsRootView: View {
    let state: AppState
    let onReturnToSplash: () -> Void

    @Environment(\.palette) private var palette
    @State private var route: DevToolsRoute = .landing

    var body: some View {
        ZStack {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Group {
                    switch route {
                    case .landing:
                        DevToolsLandingView(
                            onOpenSender: { route = .sender },
                            onOpenReceiver: { route = .receiver },
                            onOpenBakeoff: { route = .graniteBakeoff }
                        )
                    case .sender:
                        SenderPlaybackView(onBack: { route = .landing })
                    case .receiver:
                        ReceiverPlaceholderView(onBack: { route = .landing })
                    case .graniteBakeoff:
                        GraniteBakeoffView(state: state, onBack: { route = .landing })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("DevTools")
                .font(.system(size: 16, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)

            Text(headerSubtitle)
                .tccc(.labelSmall)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)

            Spacer(minLength: 12)

            if route != .landing {
                HeaderButton(title: "Back", systemImage: "chevron.left") {
                    route = .landing
                }
            }

            HeaderButton(title: "Splash", systemImage: "rectangle.portrait.and.arrow.right") {
                onReturnToSplash()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: Layout.pageHeaderHeight)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }

    private var headerSubtitle: String {
        switch route {
        case .landing:        "Sender / Receiver / Bake-off"
        case .sender:         "TTS Sender"
        case .receiver:       "Receiver Stub"
        case .graniteBakeoff: "Granite Bake-off"
        }
    }
}

private enum DevToolsRoute {
    case landing
    case sender
    case receiver
    case graniteBakeoff
}

private struct HeaderButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .heavy))
                Text(title)
                    .tccc(.labelSmall)
                    .textCase(.uppercase)
            }
            .foregroundStyle(palette.fg)
            .padding(.horizontal, 10)
            .frame(minHeight: Layout.minHitTarget)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}
