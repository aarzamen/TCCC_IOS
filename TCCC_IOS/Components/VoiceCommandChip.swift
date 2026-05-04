import SwiftUI

struct VoiceCommandChip: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.fg1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(palette.bg2)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}
