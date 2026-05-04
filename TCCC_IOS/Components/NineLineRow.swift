import SwiftUI

struct NineLineRow: View {
    let entry: NineLineEntry
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Number column
            Text(numberLabel)
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
                .frame(width: 28, alignment: .center)

            // Icon column
            Image(systemName: entry.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            // Label + value
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                Text(entry.value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .tracking(0.3)
                    .monospacedDigit()
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
            .padding(.leading, 4)

            Spacer(minLength: 0)

            // Right badge
            HStack(spacing: 4) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 9, weight: .semibold))
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(badgeColor)
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private var numberLabel: String {
        String(format: "%01d", entry.number)
    }

    private var statusColor: Color {
        switch entry.status {
        case .crit: palette.crit
        case .warn: palette.warn
        case .auto: palette.fg
        case .ok:   palette.fg
        }
    }

    private var badgeText: String { entry.isAuto ? "GPS" : "EDIT" }

    private var badgeIcon: String {
        entry.isAuto ? "location.fill" : "pencil"
    }

    private var badgeColor: Color {
        entry.isAuto ? palette.accent : palette.fg3
    }
}
