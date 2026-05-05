import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.

/// Footer chrome — always present at the bottom of every screen. Hosts:
///   - swipe affordances (← prev screen / next screen →)
///   - lifecycle quick-tap buttons (NEW / END / WIPE) that raise a
///     `ConfirmationBanner` at the top of the screen on tap
///   - settings + quick-actions buttons
struct FooterHints: View {
    let state: AppState
    let leadingLabel: String?
    let trailingLabel: String?

    @Environment(\.palette) private var palette

    init(
        state: AppState,
        leadingLabel: String? = nil,
        trailingLabel: String? = nil
    ) {
        self.state = state
        self.leadingLabel = leadingLabel
        self.trailingLabel = trailingLabel
    }

    var body: some View {
        HStack(spacing: 0) {
            previousArrow

            Spacer(minLength: 8)

            actionButtons

            Spacer(minLength: 8)

            nextArrow
        }
        .padding(.vertical, 4)
        .padding(.leading, 16)
        .padding(.trailing, 16 + Layout.homeIndicatorClearance)
        .frame(height: max(Layout.footerHintsHeight, 36))
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
        .playgroundEditable(
            ElementID.footerHints("bar"),
            hint: ElementHint(label: "Footer hints", supports: [.visibility, .frame])
        )
    }

    // MARK: - Sides

    private var previousArrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left")
                .font(.system(size: 11, weight: .semibold))
            if let leadingLabel {
                Text(leadingLabel)
                    .tccc(.labelSmall)
                    .textCase(.uppercase)
            }
        }
        .foregroundStyle(palette.fg2)
        .opacity(leadingLabel == nil ? 0.0 : 1.0)
    }

    private var nextArrow: some View {
        HStack(spacing: 6) {
            if let trailingLabel {
                Text(trailingLabel)
                    .tccc(.labelSmall)
                    .textCase(.uppercase)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(palette.accent)
        .opacity(trailingLabel == nil ? 0.0 : 1.0)
    }

    // MARK: - Center action row

    private var actionButtons: some View {
        HStack(spacing: 6) {
            actionButton(
                label: "New",
                icon: "person.crop.circle.badge.plus",
                tint: palette.fg
            ) {
                state.requestConfirmation(.newPatient)
            }

            actionButton(
                label: "End",
                icon: "checkmark.shield.fill",
                tint: palette.fg
            ) {
                state.requestConfirmation(.endCare)
            }

            actionButton(
                label: "Wipe",
                icon: "trash.fill",
                tint: palette.crit
            ) {
                state.requestConfirmation(.wipe)
            }

            divider

            actionButton(
                label: "Set",
                icon: "gearshape",
                tint: palette.fg
            ) {
                state.settingsOpen = true
            }

            actionButton(
                label: "Act",
                icon: "plus.app",
                tint: palette.fg
            ) {
                state.quickActionsOpen = true
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(width: Layout.hairline, height: 22)
            .padding(.horizontal, 4)
    }

    private func actionButton(
        label: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 38, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
