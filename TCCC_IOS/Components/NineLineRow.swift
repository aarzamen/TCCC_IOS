import SwiftUI

struct NineLineRow: View {
    let entry: NineLineEntry
    var onEdit: (() -> Void)? = nil
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

            if let onEdit, entry.number != 1 {
                Button(action: onEdit) {
                    Label(entry.value == "—" ? "ADD" : "EDIT", systemImage: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 70, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(palette.accent)
            } else {
                Label(badgeText, systemImage: badgeIcon)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(badgeColor)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
    }

    private var numberLabel: String {
        String(format: "%01d", entry.number)
    }

    private var statusColor: Color {
        switch entry.status {
        case .crit:    palette.crit
        case .warn:    palette.warn
        case .auto:    palette.fg
        case .ok:      palette.fg
        case .pending: palette.crit   // unverified — surface as crit
        }
    }

    private var badgeText: String {
        switch entry.status {
        case .pending: entry.number == 1 ? "NO FIX" : "NEEDED"
        case .auto: "GPS"
        case .ok, .warn, .crit: entry.isAuto ? "GPS" : "EDIT"
        }
    }

    private var badgeIcon: String {
        switch entry.status {
        case .pending: "exclamationmark.triangle.fill"
        case .auto: "location.fill"
        case .ok, .warn, .crit: entry.isAuto ? "location.fill" : "pencil"
        }
    }

    private var badgeColor: Color {
        switch entry.status {
        case .pending: palette.crit
        case .auto: palette.accent
        case .ok, .warn, .crit: entry.isAuto ? palette.accent : palette.fg3
        }
    }
}
