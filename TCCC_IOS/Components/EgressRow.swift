import SwiftUI

struct EgressRow: View {
    enum State { case armed, connected, disabled }

    let name: String
    let band: String
    let icon: String
    let state: State

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(name)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
            }
            Text(band)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .lineLimit(1)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDot)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(statusDot)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state == .connected ? palette.bg2 : Color.clear)
        .overlay(
            Rectangle()
                .strokeBorder(state == .connected ? palette.accent : palette.line, lineWidth: Layout.hairline)
        )
    }

    private var iconColor: Color {
        state == .disabled ? palette.fg3 : palette.accent
    }

    private var statusDot: Color {
        switch state {
        case .armed:    palette.warn
        case .connected: palette.accent
        case .disabled:  palette.fg3
        }
    }

    private var statusLabel: String {
        switch state {
        case .armed:    "ARMED"
        case .connected: "● CONNECTED"
        case .disabled:  "OFF"
        }
    }
}
