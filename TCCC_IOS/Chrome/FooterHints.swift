import SwiftUI

/// Footer chrome — always present at the bottom of every screen. Hosts:
///   - swipe affordances (← prev screen / next screen →)
///   - lifecycle quick-tap buttons (NEW / END) that raise a `ConfirmationBanner`
///     at the top of the screen on tap
///   - WIPE: a compact hold-3s affordance, visually isolated in a crit-colored
///     zone so a gloved operator can never confuse it with NEW
///   - settings + quick-actions buttons
struct FooterHints: View {
    let state: AppState
    let leadingLabel: String?
    let trailingLabel: String?

    @Environment(\.palette) private var palette

    // Hold-to-wipe state (mirrors the SettingsOverlay inline pattern)
    @State private var wipeProgress: CGFloat = 0
    @State private var wipeTask: Task<Void, Never>?
    private let wipeDuration: Double = 3.0

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
        .frame(height: max(Layout.footerHintsHeight, Layout.footerHintHeight + 8))
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
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
            // NEW — plain tap → raises non-destructive confirmation banner
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

            // Visual separator: WIPE lives in its own crit-colored zone to
            // the right of all non-destructive actions.
            divider

            wipeButton

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

            if state.graniteReviewQueue.count > 0 {
                divider

                reviewButton
            }
        }
    }

    // MARK: - Hold-3s Wipe affordance

    /// Compact hold-3s Wipe button. The operator must press and hold for 3
    /// seconds before `wipeSession()` fires — identical hold duration to the
    /// SettingsOverlay WIPE and consistent with CLAUDE.md hard constraint #4.
    /// A `crit`-colored progress bar sweeps left-to-right during the hold so
    /// intent is unambiguous.
    private var wipeButton: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 1) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.crit)
                Text("Wipe")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(palette.crit)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: Layout.footerHintHeight)
            .contentShape(Rectangle())
            .gesture(wipeHoldGesture)

            // Progress bar sweeps left-to-right during hold
            Rectangle()
                .fill(palette.crit)
                .frame(width: wipeProgress * 44, height: 2)
                .opacity(wipeProgress > 0 ? 1 : 0)
        }
    }

    private var wipeHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard wipeTask == nil else { return }
                wipeProgress = 0
                Haptics.tap(.light)
                let start = Date()
                wipeTask = Task { @MainActor in
                    while !Task.isCancelled {
                        let elapsed = Date().timeIntervalSince(start)
                        let p = min(1, elapsed / wipeDuration)
                        wipeProgress = CGFloat(p)
                        if p >= 1 {
                            Haptics.tap(.heavy)
                            state.wipeSession()
                            wipeProgress = 0
                            wipeTask = nil
                            return
                        }
                        try? await Task.sleep(nanoseconds: 30_000_000)
                    }
                }
            }
            .onEnded { _ in
                wipeTask?.cancel()
                wipeTask = nil
                if wipeProgress < 1 {
                    withAnimation(.fast) {
                        wipeProgress = 0
                    }
                }
            }
    }

    private var reviewButton: some View {
        Button {
            Haptics.tap()
            state.reviewOpen = true
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ok)
                    Text("Review")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 6)
                .frame(minWidth: 44, minHeight: Layout.footerHintHeight)

                // Badge showing pending count
                Text("\(state.graniteReviewQueue.count)")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(palette.bg)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(palette.ok)
                    .clipShape(Capsule())
                    .offset(x: -2, y: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        Button {
            Haptics.tap()
            action()
        } label: {
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
            .frame(minWidth: 44, minHeight: Layout.footerHintHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
