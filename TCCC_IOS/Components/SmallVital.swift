import SwiftUI

/// Small vitals card — bottom row on Screen 02 (RESP, GCS, TEMP, CAP RE).
///
/// Spec (design brief §5.2):
/// - 1px line border, bg-1, padding 8×12
/// - Label 10pt with optional small icon
/// - Value 26pt mono 700, color = `palette.warn` when `isWarn` else `palette.fg`
/// - Unit 10pt meta in `palette.fg2`
struct SmallVital: View {
    let label: String
    let value: String
    let unit: String
    let isWarn: Bool
    let icon: String

    @Environment(\.palette) private var palette

    init(
        label: String,
        value: String,
        unit: String,
        isWarn: Bool,
        icon: String
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.isWarn = isWarn
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.fg2)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .tccc(.smallVital)
                    .foregroundStyle(isWarn ? palette.warn : palette.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg1)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }
}
