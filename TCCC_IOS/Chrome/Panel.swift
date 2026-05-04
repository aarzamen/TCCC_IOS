import SwiftUI

struct Panel<Content: View>: View {
    let title: String
    let titleIcon: String?
    let action: String?
    let accent: Bool
    let padded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.palette) private var palette

    init(
        _ title: String,
        titleIcon: String? = nil,
        action: String? = nil,
        accent: Bool = false,
        padded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleIcon = titleIcon
        self.action = action
        self.accent = accent
        self.padded = padded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padded ? Layout.panelPadding : 0)
        }
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(accent ? palette.accentDim : palette.line, lineWidth: Layout.hairline)
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                if let titleIcon {
                    Image(systemName: titleIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.fg)
                }
                Text(title)
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 0)

            if let action {
                Text(action)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.7)
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                    .textCase(.uppercase)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }
}
