import SwiftUI

struct TransmitScript: View {
    let entries: [NineLineEntry]
    let onReview: () -> Void
    let onTransmit: () -> Void
    let onGenerate: () -> Void
    let generatedScript: String?
    let isGenerating: Bool
    let generationError: String?

    @Environment(\.palette) private var palette
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?
    private let holdDuration: Double = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            scriptCard
            generationStatusLine
            actionsRow
        }
    }

    private var scriptCard: some View {
        Group {
            if let generated = generatedScript, !generated.isEmpty {
                generatedScriptView(generated)
            } else {
                fallbackScriptView
            }
        }
    }

    private var fallbackScriptView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MEDEVAC, MEDEVAC,")
                .foregroundStyle(palette.accent)
            Text("THIS IS MEDIC,")
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

    private func generatedScriptView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(text.components(separatedBy: "\n"), id: \.self) { line in
                Text(line.isEmpty ? " " : line)
                    .foregroundStyle(line.lowercased().contains("dustoff") ? palette.accent : palette.fg)
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
                .strokeBorder(palette.accentDim, lineWidth: Layout.hairline)
        )
    }

    private var scriptLines: [String] {
        var out: [String] = []
        for entry in entries.prefix(5) {
            out.append("LINE \(entry.number): \(entry.value.uppercased())")
        }
        return out
    }

    @ViewBuilder
    private var generationStatusLine: some View {
        if isGenerating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Generating radio call · on-device")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                    .textCase(.uppercase)
            }
        } else if let err = generationError {
            Text(err)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.crit)
                .lineLimit(2)
        } else if generatedScript != nil {
            Text("Generated · review before transmit")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.accent)
                .textCase(.uppercase)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            BigButton(
                isGenerating ? "Generating…" : (generatedScript == nil ? "Generate" : "Regenerate"),
                systemImage: "wand.and.stars",
                style: .standard,
                action: onGenerate
            )
            .disabled(isGenerating)

            BigButton("Review", systemImage: "slider.horizontal.3", style: .standard, action: onReview)

            ZStack(alignment: .bottomLeading) {
                BigButton(
                    "Transmit",
                    systemImage: "paperplane.fill",
                    style: .accent
                ) { /* handled by long-press gesture below */ }
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
