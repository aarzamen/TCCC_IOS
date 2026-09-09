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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(generatedScript == nil ? "DETERMINISTIC WORKSHEET" : "LLM DRAFT · REVIEW WORDING")
                        .font(.caption.bold()).foregroundStyle(palette.accent)
                    if let generatedScript {
                        Text(generatedScript).textSelection(.enabled)
                    } else {
                        ForEach(entries) { entry in
                            Text("LINE \(entry.number): \(entry.value)")
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            .background(palette.bg)
            if let generationError {
                Text(generationError).font(.caption).foregroundStyle(palette.crit)
            }
            let missing = entries.filter { !$0.isVerifiedForTransmit }.count
            Text(missing == 0 ? "All lines entered · review before use" : "\(missing) lines need information")
                .font(.caption).foregroundStyle(missing == 0 ? palette.fg2 : palette.warn)
            HStack(spacing: 6) {
                BigButton(isGenerating ? "Generating…" : "Draft wording", systemImage: "wand.and.stars", style: .standard, action: onGenerate)
                    .disabled(isGenerating)
                BigButton("Edit fields", systemImage: "pencil", style: .standard, action: onReview)
                BigButton("Call made", systemImage: "checkmark.bubble", style: .standard, action: onTransmit)
            }
        }
    }
}
