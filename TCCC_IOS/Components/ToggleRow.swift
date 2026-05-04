import SwiftUI

struct ToggleRow: View {
    let label: String
    let detail: String?
    @Binding var isOn: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(palette.fg)
                        .textCase(.uppercase)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.fg2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                toggleVisual
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.line)
                    .frame(height: Layout.hairline)
            }
        }
        .buttonStyle(.plain)
    }

    private var toggleVisual: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(isOn ? palette.accentDim : palette.bg2)
                .frame(width: 32, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(isOn ? palette.accent : palette.line, lineWidth: 1)
                )
            RoundedRectangle(cornerRadius: 1)
                .fill(isOn ? palette.accent : palette.fg2)
                .frame(width: 12, height: 10)
                .padding(.horizontal, 1)
        }
        .animation(.fast, value: isOn)
    }
}
