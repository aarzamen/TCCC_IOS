import SwiftUI

public struct RadioScriptLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let text: String
    public init(id: String, label: String, text: String) { self.id = id; self.label = label; self.text = text }
}

struct ScriptSelection {
    private var sourceID: String?
    private var lines: [RadioScriptLine] = []
    private var selected = 0
    func index(sourceID: String, lines: [RadioScriptLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        guard self.sourceID == sourceID, self.lines == lines, lines.indices.contains(selected) else { return 0 }
        return selected
    }
    mutating func select(_ index: Int, sourceID: String, lines: [RadioScriptLine]) {
        self.sourceID = sourceID; self.lines = lines
        selected = lines.indices.contains(index) ? index : 0
    }
}

/// Manual visual guide only. Speech, generation, clipboard and transmission I/O
/// belong to callers. No timed progression or delivery status is simulated here.
/// Lines stay in caller order, including repeated IDs. Changing the source ID or
/// any line content resets the guide to the first line.
public struct RadioScript: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @State private var selection = ScriptSelection()
    private let sourceID: String
    private let lines: [RadioScriptLine]
    private let onCopy: (() -> Void)?
    private let onRegenerate: (() -> Void)?

    public init(sourceID: String, lines: [RadioScriptLine], onCopy: (() -> Void)? = nil, onRegenerate: (() -> Void)? = nil) {
        self.sourceID = sourceID; self.lines = lines; self.onCopy = onCopy; self.onRegenerate = onRegenerate
    }

    public var body: some View {
        let index = selection.index(sourceID: sourceID, lines: lines)
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual read-along").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Visual guide — advance each line yourself.").font(.caption).foregroundStyle(theme.color(.muted))
            if lines.isEmpty {
                Text("No script supplied").foregroundStyle(theme.color(.muted)).frame(minHeight: metrics.row)
            } else {
                Text("Line \((index ?? 0) + 1) of \(lines.count)").font(.caption.monospaced())
                // Index identity renders every supplied line even if caller IDs repeat.
                ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                    lineButton(line, index: offset, selected: offset == index)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: max(150, metrics.tap)), alignment: .leading)], alignment: .leading, spacing: 10) {
                ActionButton("Previous line", variant: .ghost, systemImage: "chevron.left", isEnabled: (index ?? 0) > 0,
                             disabledReason: lines.isEmpty ? "No script supplied" : "At first line") { select((index ?? 0) - 1) }
                ActionButton("Next line", variant: .navigate, systemImage: "chevron.right", isEnabled: index != nil && (index ?? 0) + 1 < lines.count,
                             disabledReason: lines.isEmpty ? "No script supplied" : "At last line") { select((index ?? 0) + 1) }
                ActionButton("Restart guide", variant: .neutral, systemImage: "arrow.counterclockwise", isEnabled: !lines.isEmpty,
                             disabledReason: "No script supplied") { select(0) }
                ActionButton("Regenerate script", variant: .ai, systemImage: "sparkles", disabledReason: "Generation unavailable — no action provided", action: onRegenerate)
                ActionButton("Copy script", variant: .neutral, systemImage: "doc.on.doc", isEnabled: !lines.isEmpty,
                             disabledReason: lines.isEmpty ? "No script supplied" : "Copy unavailable — no action provided", action: onCopy)
            }
        }
        .padding(14).foregroundStyle(theme.color(.ink))
        .onChange(of: sourceID) { _, _ in select(0) }
        .onChange(of: lines) { _, _ in select(0) }
    }

    private func select(_ index: Int) { selection.select(index, sourceID: sourceID, lines: lines) }

    private func lineButton(_ line: RadioScriptLine, index: Int, selected: Bool) -> some View {
        Button { select(index) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if selected { Image(systemName: "arrow.right").accessibilityHidden(true) }
                    Text(line.label).font(.caption.weight(.semibold))
                }
                Text(line.text).font(.body.monospaced()).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(minWidth: metrics.tap, maxWidth: .infinity, minHeight: metrics.tap, alignment: .leading)
            .foregroundStyle(selected ? Theme.base.palette.background.color : theme.color(.ink))
            .background(selected ? theme.color(.accent) : theme.palette.panel2.color, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("\(line.label), \(line.text)")
        .accessibilityValue(selected ? "Current line" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
private struct RadioScriptExample: View {
    let empty: Bool
    @State private var revision = 1
    @State private var feedback = "No synthetic callback yet"
    private var lines: [RadioScriptLine] {
        empty ? [] : [RadioScriptLine(id: "1", label: "Synthetic line one", text: "Example script revision \(revision)."),
                      RadioScriptLine(id: "2", label: "Synthetic line two", text: "Read and manually advance this example; it produces no audio or transmission.")]
    }
    var body: some View {
        VStack(alignment: .leading) {
            RadioScript(sourceID: "synthetic", lines: lines,
                        onCopy: empty ? nil : { feedback = "Synthetic copy callback accepted" },
                        onRegenerate: empty ? nil : { revision += 1; feedback = "Synthetic source changed" })
            Text(feedback).font(.caption)
        }
    }
}
#Preview("RadioScript · matrix") {
    PreviewMatrix("RadioScript") { RadioScriptExample(empty: $0.isEmpty) }
}
#endif
