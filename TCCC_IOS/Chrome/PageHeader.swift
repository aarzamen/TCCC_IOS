import SwiftUI

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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                indexLabel
                Text(screen.kicker)
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg2)
                Text(screen.title)
                    .tccc(.h1)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 0)

            if let label = trailingKickerLabel, let value = trailingKickerValue {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(label)
                        .tccc(.label)
                        .foregroundStyle(palette.fg2)
                    Text(value)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }

    private var indexLabel: some View {
        Text(String(format: "%02d / %02d", screen.rawValue + 1, total))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .monospacedDigit()
            .foregroundStyle(palette.accent)
    }
}
