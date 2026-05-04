import SwiftUI

struct ThemeOptCard: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                swatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.fg)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.fg2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                radioSquare
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.bg2 : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(isSelected ? palette.accent : palette.line, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        switch theme {
        case .tactical: "Default · NVG-safe deep red"
        case .dark:     "High-contrast amber on neutral"
        case .light:    "Daylight warm gray"
        }
    }

    private var swatch: some View {
        let p = theme.palette
        return ZStack {
            Rectangle().fill(p.bg).frame(width: 36, height: 24)
            VStack(spacing: 1.5) {
                Rectangle().fill(p.accent).frame(height: 1.5)
                Rectangle().fill(p.fg).frame(height: 1.5)
                Rectangle().fill(p.fg2).frame(height: 1.5)
            }
            .padding(4)
        }
        .frame(width: 36, height: 24)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: 0.5)
        )
    }

    private var radioSquare: some View {
        ZStack {
            Rectangle()
                .strokeBorder(isSelected ? palette.accent : palette.fg2, lineWidth: 1)
                .frame(width: 12, height: 12)
            if isSelected {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 6)
            }
        }
    }
}
