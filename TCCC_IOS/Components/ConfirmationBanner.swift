import SwiftUI

/// Top-positioned confirmation overlay for lifecycle actions (New / End /
/// Wipe). Appears far from the bottom-bar buttons so a stray double-tap
/// can't accidentally confirm. YES on the right, NO on the left, both
/// large enough for gloved hands.
struct ConfirmationBanner: View {
    let state: AppState
    @Environment(\.palette) private var palette

    var body: some View {
        if let action = state.pendingConfirmation {
            ZStack(alignment: .top) {
                scrim
                banner(for: action)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .transition(.opacity)
        }
    }

    private var scrim: some View {
        Color.black.opacity(0.72)
            .ignoresSafeArea()
            .onTapGesture {
                state.cancelConfirmation()
            }
    }

    private func banner(for action: ConfirmationAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Big "ARE YOU SURE?" header
            HStack(alignment: .firstTextBaseline) {
                Text("Are you sure?")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(action.isDestructive ? palette.crit : palette.accent)
                    .textCase(.uppercase)

                Spacer(minLength: 12)

                Button {
                    state.cancelConfirmation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.fg2)
                        .padding(8)
                        .frame(width: Layout.minHitTarget, height: Layout.minHitTarget)
                        .overlay(
                            Rectangle()
                                .strokeBorder(palette.line, lineWidth: Layout.hairline)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }

            // Action headline
            Text(action.headline)
                .font(.system(size: 17, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(palette.fg)

            // Detail
            Text(action.detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.fg2)
                .fixedSize(horizontal: false, vertical: true)

            // Big YES / NO buttons
            HStack(spacing: 12) {
                Button {
                    state.cancelConfirmation()
                } label: {
                    bigChoiceLabel("No, cancel", style: .neutral)
                }
                .buttonStyle(.plain)

                Button {
                    Task { @MainActor in await state.confirmPending() }
                } label: {
                    bigChoiceLabel(action.confirmLabel, style: action.isDestructive ? .destructive : .accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(action.isDestructive ? palette.crit : palette.accent, lineWidth: 2)
        )
    }

    private enum ChoiceStyle {
        case neutral
        case accent
        case destructive
    }

    private func bigChoiceLabel(_ title: String, style: ChoiceStyle) -> some View {
        let bg: Color
        let border: Color
        let fg: Color
        switch style {
        case .neutral:
            bg = palette.bg2
            border = palette.line
            fg = palette.fg
        case .accent:
            bg = palette.accentDim
            border = palette.accent
            fg = palette.fg
        case .destructive:
            bg = palette.crit.opacity(0.4)
            border = palette.crit
            fg = palette.fg
        }
        return Text(title)
            .font(.system(size: 18, weight: .heavy))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(bg)
            .overlay(
                Rectangle()
                    .strokeBorder(border, lineWidth: 2)
            )
    }
}
