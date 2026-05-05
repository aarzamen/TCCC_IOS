import SwiftUI

/// 2×2 grid item for transmit destinations on Screen 05 (Handoff).
///
/// Toggle-button: tap selects. Active state uses `palette.accent` border and
/// `palette.bg2` background. Hit target ≥ 44pt per CLAUDE.md (gloved-hand).
struct DestCard: View {
    let icon: String
    let label: String       // "QR · OFFLINE", "NFC TAP"
    let isActive: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isActive ? palette.accent : palette.fg1)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(isActive ? palette.accent : palette.fg)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Layout.minHitTarget)
            .background(isActive ? palette.bg2 : palette.bg)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        isActive ? palette.accent : palette.line,
                        lineWidth: isActive ? 1.5 : Layout.hairline
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
