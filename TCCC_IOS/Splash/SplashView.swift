import SwiftUI

struct SplashView: View {
    let onOpenMain: () -> Void
    let onOpenDevTools: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.bg
                .ignoresSafeArea()

            VStack(spacing: Layout.gridGap) {
                header

                HStack(spacing: Layout.gridGap) {
                    SplashChoiceCard(
                        title: "TCCC.ai",
                        subtitle: "Casualty management",
                        systemImage: "cross.case.fill",
                        style: .accent,
                        action: onOpenMain
                    )

                    SplashChoiceCard(
                        title: "DevTools",
                        subtitle: "Scenario playback",
                        systemImage: "waveform.badge.magnifyingglass",
                        style: .standard,
                        action: onOpenDevTools
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.vertical, Layout.outerPadding)
            .padding(.leading, Layout.dynamicIslandClearance)
            .padding(.trailing, Layout.homeIndicatorClearance)
        }
    }

    private var header: some View {
        Panel("Launch", titleIcon: "shield.lefthalf.filled", action: "offline", padded: true) {
            HStack(spacing: 10) {
                Text("Swift TCCC")
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)

                Rectangle()
                    .fill(palette.line)
                    .frame(width: Layout.hairline, height: 18)

                Text("Select Role")
                    .tccc(.h1)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

private struct SplashChoiceCard: View {
    enum Style {
        case standard
        case accent
    }

    let title: String
    let subtitle: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(iconColor)

                VStack(spacing: 8) {
                    Text(subtitle)
                        .tccc(.labelSmall)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                        .lineLimit(1)

                    Text(title)
                        .tccc(.h1)
                        .foregroundStyle(palette.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Rectangle()
                        .fill(borderColor)
                        .frame(height: Layout.hairline)
                        .frame(maxWidth: 96)
                }
            }
            .padding(24)
            .frame(
                maxWidth: .infinity,
                minHeight: Layout.bigButtonHeight * 3,
                maxHeight: .infinity
            )
            .background(backgroundColor)
            .overlay(
                Rectangle()
                    .strokeBorder(borderColor, lineWidth: Layout.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: palette.bg1
        case .accent:   palette.bg2
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard: palette.line
        case .accent:   palette.accent
        }
    }

    private var iconColor: Color {
        switch style {
        case .standard: palette.fg1
        case .accent:   palette.accent
        }
    }
}

#Preview {
    SplashView(onOpenMain: {}, onOpenDevTools: {})
        .environment(\.palette, Theme.dark.palette)
}
