import SwiftUI

struct FooterHints: View {
    let leadingLabel: String?
    let trailingLabel: String?
    let onSettings: (() -> Void)?
    let onQuickActions: (() -> Void)?

    @Environment(\.palette) private var palette

    init(
        leadingLabel: String? = nil,
        trailingLabel: String? = nil,
        onSettings: (() -> Void)? = nil,
        onQuickActions: (() -> Void)? = nil
    ) {
        self.leadingLabel = leadingLabel
        self.trailingLabel = trailingLabel
        self.onSettings = onSettings
        self.onQuickActions = onQuickActions
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.fg2)
                Button {
                    onSettings?()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(onSettings != nil ? palette.fg : palette.fg2)
                        .frame(width: Layout.minHitTarget, height: Layout.minHitTarget)
                }
                .buttonStyle(.plain)
                .disabled(onSettings == nil)

                Image(systemName: "rectangle.portrait")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.fg2)

                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.fg2)
                Button {
                    onQuickActions?()
                } label: {
                    Image(systemName: "plus.app")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(onQuickActions != nil ? palette.fg : palette.fg2)
                        .frame(width: Layout.minHitTarget, height: Layout.minHitTarget)
                }
                .buttonStyle(.plain)
                .disabled(onQuickActions == nil)
            }

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
        .padding(.vertical, 4)
        .padding(.leading, 24)
        .padding(.trailing, 24 + Layout.homeIndicatorClearance)
        .frame(height: Layout.footerHintsHeight + 8)
        .background(palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }
}
