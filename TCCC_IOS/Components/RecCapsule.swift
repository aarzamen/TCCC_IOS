import SwiftUI

struct RecCapsule: View {
    let isRecording: Bool
    let elapsed: String

    @Environment(\.palette) private var palette
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isRecording ? palette.rec : palette.fg3)
                .frame(width: 14, height: 14)
                .scaleEffect(isRecording && pulse ? 0.85 : 1.0)
                .opacity(isRecording && pulse ? 0.35 : 1.0)
                .task(id: isRecording) {
                    guard isRecording else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        withAnimation(.easeInOut(duration: 0.6)) {
                            pulse.toggle()
                        }
                    }
                }

            Text(elapsed)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.fg)

            Spacer(minLength: 0)

            Text("48k · 16b")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(palette.fg2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }
}
