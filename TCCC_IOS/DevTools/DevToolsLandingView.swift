import SwiftUI

struct DevToolsLandingView: View {
    let onOpenSender: (() -> Void)?
    let onOpenReceiver: () -> Void
    let onOpenBakeoff: (() -> Void)?

    @Environment(\.palette) private var palette

    init(
        onOpenSender: (() -> Void)? = nil,
        onOpenReceiver: @escaping () -> Void,
        onOpenBakeoff: (() -> Void)? = nil
    ) {
        self.onOpenSender = onOpenSender
        self.onOpenReceiver = onOpenReceiver
        self.onOpenBakeoff = onOpenBakeoff
    }

    var body: some View {
        VStack(spacing: Layout.gridGap) {
            Spacer(minLength: 0)

            HStack(spacing: Layout.gridGap) {
                modeCard(
                    title: "Sender",
                    subtitle: onOpenSender == nil ? "Pending" : "Read scenario scripts aloud",
                    icon: "speaker.wave.3.fill",
                    accent: true,
                    isEnabled: onOpenSender != nil,
                    action: onOpenSender
                )

                modeCard(
                    title: "Receiver",
                    subtitle: "Capture peer device input",
                    icon: "dot.radiowaves.left.and.right",
                    accent: false,
                    isEnabled: true,
                    action: onOpenReceiver
                )

                modeCard(
                    title: "Bake-off",
                    subtitle: onOpenBakeoff == nil ? "Pending" : "Granite Speech 5-bit",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    accent: false,
                    isEnabled: onOpenBakeoff != nil,
                    action: onOpenBakeoff
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Layout.outerPadding)
        .padding(.leading, Layout.dynamicIslandClearance)
        .padding(.trailing, Layout.homeIndicatorClearance)
    }

    private func modeCard(
        title: String,
        subtitle: String,
        icon: String,
        accent: Bool,
        isEnabled: Bool,
        action: (() -> Void)?
    ) -> some View {
        Button {
            guard isEnabled else { return }
            Haptics.tap()
            action?()
        } label: {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(accent ? palette.accent : palette.fg1)

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
                }
            }
            .padding(24)
            .frame(
                maxWidth: .infinity,
                minHeight: Layout.bigButtonHeight * 3,
                maxHeight: .infinity
            )
            .background(accent ? palette.bg2 : palette.bg1)
            .overlay(
                Rectangle()
                    .strokeBorder(accent ? palette.accent : palette.line, lineWidth: Layout.hairline)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
