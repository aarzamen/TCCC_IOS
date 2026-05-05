import SwiftUI

/// Non-blocking warning chips rendered in a horizontal stack. Used to
/// surface rubric-derived advisories (2026 §11 AVPU-before-ketamine,
/// §6 ASM/CLS TQ-conversion scope) without interrupting the medic's
/// flow. Tap to dismiss is intentionally NOT supported — these warnings
/// reflect protocol state and clear themselves when the underlying
/// state changes.
struct WarningBanner: View {
    let warnings: [AppState.TCCCWarning]
    @Environment(\.palette) private var palette

    /// Tracks the warning set we last fired a haptic for. We notify on
    /// every transition where a new warning enters the set (or the set
    /// goes from empty → non-empty); identical re-renders stay silent.
    @State private var lastNotified: Set<AppState.TCCCWarning> = []

    var body: some View {
        Group {
            if warnings.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 4) {
                    ForEach(warnings, id: \.self) { warning in
                        chip(for: warning)
                    }
                }
            }
        }
        .onAppear { fireIfNew() }
        .onChange(of: warnings) { _, _ in fireIfNew() }
    }

    /// Fire `.warning` exactly once per *new* warning. Re-renders with
    /// the same set stay silent; warnings clearing then reappearing does
    /// re-fire (the cleared state resets `lastNotified`).
    private func fireIfNew() {
        let current = Set(warnings)
        if current.isEmpty {
            lastNotified = []
            return
        }
        if !current.isSubset(of: lastNotified) {
            Haptics.notify(.warning)
        }
        lastNotified = current
    }

    private func chip(for warning: AppState.TCCCWarning) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.warn)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.warn)
                Text(warning.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(palette.warn.opacity(0.08))
        .overlay(
            Rectangle()
                .strokeBorder(palette.warn, lineWidth: Layout.hairline)
        )
    }
}

extension AppState.TCCCWarning {
    fileprivate var title: String {
        switch self {
        case .avpuBeforeKetamine: "AVPU REQUIRED"
        case .tqConversionScope:  "TQ CONVERSION · SCOPE"
        }
    }

    fileprivate var detail: String {
        switch self {
        case .avpuBeforeKetamine:
            "Document AVPU prior to ketamine per 2026 §11."
        case .tqConversionScope:
            "TQ conversion beyond 2 hours requires CMC/CPP direction per 2026 §6."
        }
    }
}
