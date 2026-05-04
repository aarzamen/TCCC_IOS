import SwiftUI

struct RFRow: View {
    let name: String        // "WI-FI", "BLUETOOTH", ...
    let band: String        // "2.4 / 5 GHz", "2.4 GHz", ...
    let icon: String        // SF Symbol

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.fg3)
                ZStack {
                    Text(name)
                        .strikethrough(true, color: palette.fg3)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                }
            }
            Text(band)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text("OFF · 0 dBm")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(palette.fg2)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text("LOCK")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                }
                .foregroundStyle(palette.accent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }
}
