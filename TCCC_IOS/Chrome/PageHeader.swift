import SwiftUI

/// Compact single-line page header for landscape iPhone.
///
/// Replaces the design's stacked-column header (index above kicker above
/// title) with a single horizontal row to reclaim ~60pt of vertical space.
/// The full canvas on iPhone 17 Pro landscape is ~430pt — every pt saved
/// up here is one less pt the panels below have to fight for.
struct PageHeader: View {
    let screen: AppState.Screen
    let total: Int
    let trailingKickerLabel: String?
    let trailingKickerValue: String?

    @Environment(\.palette) private var palette

    init(
        screen: AppState.Screen,
        total: Int,
        trailingKickerLabel: String? = nil,
        trailingKickerValue: String? = nil
    ) {
        self.screen = screen
        self.total = total
        self.trailingKickerLabel = trailingKickerLabel
        self.trailingKickerValue = trailingKickerValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            indexLabel
                .fixedSize(horizontal: true, vertical: false)

            Text(screen.title)
                .font(.system(size: 18, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(screen.kicker)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let label = trailingKickerLabel, let value = trailingKickerValue {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg1)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }

    private var indexLabel: some View {
        Text(String(format: "%02d / %02d", screen.rawValue + 1, total))
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .tracking(0.8)
            .monospacedDigit()
            .foregroundStyle(palette.accent)
    }
}
