import SwiftUI

struct BigButton: View {
    enum Style {
        case standard
        case accent
    }

    let label: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    @Environment(\.palette) private var palette

    init(
        _ label: String,
        systemImage: String,
        style: Style = .standard,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(2.0)
                    .foregroundStyle(labelColor)
                    .textCase(.uppercase)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Layout.bigButtonHeight)
            .background(backgroundColor)
            .overlay(
                Rectangle()
                    .strokeBorder(borderColor, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .standard: palette.bg1
        case .accent:   palette.accentDim
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

    private var labelColor: Color {
        switch style {
        case .standard: palette.fg
        case .accent:   palette.fg
        }
    }
}
