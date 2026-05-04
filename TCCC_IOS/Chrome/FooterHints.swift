import SwiftUI

struct FooterHints: View {
    let leadingLabel: String?
    let trailingLabel: String?

    @Environment(\.palette) private var palette

    init(leadingLabel: String? = nil, trailingLabel: String? = nil) {
        self.leadingLabel = leadingLabel
        self.trailingLabel = trailingLabel
    }

    var body: some View {
        HStack(spacing: 0) {
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

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Image(systemName: "arrow.up")
                Image(systemName: "gearshape")
                Image(systemName: "rectangle.portrait")
                Image(systemName: "arrow.down")
                Image(systemName: "plus")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.fg2)

            Spacer(minLength: 0)

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
        .padding(.vertical, 8)
        .padding(.leading, 24)
        .padding(.trailing, 24 + Layout.homeIndicatorClearance)
        .frame(height: Layout.footerHintsHeight)
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }
}
