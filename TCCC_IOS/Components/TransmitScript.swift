import SwiftUI

struct TransmitScript: View {
    let entries: [NineLineEntry]
    let onReview: () -> Void
    let onTransmit: () -> Void

    @Environment(\.palette) private var palette
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?
    private let holdDuration: Double = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            scriptCard
            actionsRow
        }
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DUSTOFF SIX, DUSTOFF SIX,")
                .foregroundStyle(palette.accent)
            Text("THIS IS HAVOC TWO ACTUAL,")
                .foregroundStyle(palette.fg)

            ForEach(scriptLines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(palette.fg)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .lineSpacing(3)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg)
        .overlay(
            Rectangle()
                .strokeBorder(palette.line, lineWidth: Layout.hairline)
        )
    }

    private var scriptLines: [String] {
        var out: [String] = []
        for entry in entries.prefix(5) {
            out.append("LINE \(entry.number): \(entry.value.uppercased())")
        }
        return out
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            BigButton("Review", systemImage: "slider.horizontal.3", style: .standard, action: onReview)

            ZStack(alignment: .bottomLeading) {
                BigButton(
                    "Transmit",
                    systemImage: "paperplane.fill",
                    style: .accent
                ) {
                    // Tap on the inner BigButton just resets the hold; only
                    // the long-press completes the action. Provide a tap-to-
                    // start-hold UX by toggling here.
                }
                .gesture(transmitHoldGesture)

                Rectangle()
                    .fill(palette.accent)
                    .frame(width: holdProgress * fullWidth, height: 2)
                    .opacity(holdProgress > 0 ? 1 : 0)
            }
        }
    }

    private var fullWidth: CGFloat { 200 }

    private var transmitHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if holdTask == nil {
                    holdProgress = 0
                    let start = Date()
                    holdTask = Task { @MainActor in
                        while !Task.isCancelled {
                            let elapsed = Date().timeIntervalSince(start)
                            let p = min(1, elapsed / holdDuration)
                            holdProgress = CGFloat(p)
                            if p >= 1 {
                                onTransmit()
                                holdProgress = 0
                                holdTask = nil
                                return
                            }
                            try? await Task.sleep(nanoseconds: 30_000_000)
                        }
                    }
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                if holdProgress < 1 {
                    withAnimation(.fast) {
                        holdProgress = 0
                    }
                }
            }
    }
}
