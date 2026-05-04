import SwiftUI

struct Field: View {
    let label: String
    let value: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.fg2)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }
}
