import SwiftUI

public enum ExportReadiness: Equatable, Sendable {
    case ready
    case pending(String)
    case unavailable(String)
    public var title: String {
        switch self {
        case .ready: "Ready to export"
        case .pending: "Pending"
        case .unavailable: "Unavailable"
        }
    }
    public var reason: String? {
        switch self {
        case .ready: nil
        case .pending(let reason), .unavailable(let reason): reason
        }
    }
    public func canAct(hasAction: Bool) -> Bool { self == .ready && hasAction }
}

/// Readiness is explicit. Accepting the callback never implies export or delivery succeeded.
public struct ExportCard: View {
    @Environment(\.tcccTheme) private var theme
    private let name: String
    private let systemImage: String
    private let metadata: String?
    private let readiness: ExportReadiness
    private let actionTitle: String
    private let action: (() -> Void)?

    public init(name: String, systemImage: String = "doc", metadata: String? = nil, readiness: ExportReadiness,
                actionTitle: String = "Export", action: (() -> Void)? = nil) {
        self.name = name; self.systemImage = systemImage; self.metadata = metadata
        self.readiness = readiness; self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(name, systemImage: systemImage).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let metadata { Text(metadata).font(.caption.monospaced()).foregroundStyle(theme.color(.muted)).fixedSize(horizontal: false, vertical: true) }
            Label(readiness.title, systemImage: readiness == .ready ? "checkmark.circle" : "clock")
                .font(.caption.weight(.semibold)).foregroundStyle(theme.color(readiness == .ready ? .ok : .muted))
            ActionButton(actionTitle, variant: .navigate, systemImage: "square.and.arrow.up",
                         isEnabled: readiness.canAct(hasAction: action != nil),
                         disabledReason: readiness.reason ?? "Export unavailable — no action provided", action: action)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(theme.color(.ink))
        .background(theme.palette.panel2.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.line.color) }
    }
}

public enum HumanVerification: String, CaseIterable, Sendable {
    case unreviewed, verified, needsCorrection
    public var title: String {
        switch self {
        case .unreviewed: "Human verification: Not reviewed"
        case .verified: "Human verification: Verified"
        case .needsCorrection: "Human verification: Needs correction"
        }
    }
    var tone: SemanticRole {
        switch self {
        case .unreviewed: .muted
        case .verified: .ok
        case .needsCorrection: .warn
        }
    }
    var symbol: String {
        switch self {
        case .unreviewed: "questionmark.circle"
        case .verified: "checkmark.circle"
        case .needsCorrection: "exclamationmark.triangle"
        }
    }
}

enum ConfidenceDisplay {
    static func text(_ confidence: Double?) -> String {
        guard let confidence, confidence.isFinite, (0...1).contains(confidence) else { return "Unknown" }
        return confidence.formatted(.percent.precision(.fractionLength(0...2)))
    }
}

/// The caller's human verification is independent of any supplied model confidence.
public struct Provenance: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @State private var expanded = false
    private let fact: String
    private let sourceText: String?
    private let timestamp: Date?
    private let confidence: Double?
    private let verification: HumanVerification
    private let timeZone: TimeZone

    public init(fact: String, sourceText: String? = nil, timestamp: Date? = nil, confidence: Double? = nil,
                verification: HumanVerification, timeZone: TimeZone = .gmt) {
        self.fact = fact; self.sourceText = sourceText; self.timestamp = timestamp
        self.confidence = confidence; self.verification = verification; self.timeZone = timeZone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown fact" : fact).font(.body.monospaced())
                    Label(verification.title, systemImage: verification.symbol).font(.caption.weight(.semibold)).foregroundStyle(theme.color(verification.tone))
                    Text("Model confidence: \(ConfidenceDisplay.text(confidence))").font(.caption.monospaced()).foregroundStyle(theme.color(.muted))
                    Label(expanded ? "Hide source details" : "Show source details", systemImage: expanded ? "chevron.up" : "chevron.down").font(.subheadline)
                }
                .fixedSize(horizontal: false, vertical: true).padding(12)
                .frame(minWidth: metrics.tap, maxWidth: .infinity, minHeight: metrics.tap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Source: \(sourceText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "Unknown — not supplied")")
                    Text(timestamp.map { "Recorded: \(DataDisplay.date($0, timeZone: timeZone))" } ?? "Recorded time: Unknown")
                        .font(.caption.monospaced())
                }.padding(.horizontal, 12).padding(.bottom, 12).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(theme.color(.ink)).background(theme.palette.panel2.color, in: RoundedRectangle(cornerRadius: 6))
    }
}

#if DEBUG
private struct ExportExample: View {
    let empty: Bool
    @State private var count = 0
    var body: some View {
        VStack(alignment: .leading) {
            ExportCard(name: "Synthetic document", metadata: empty ? nil : "Example metadata · no file is created", readiness: empty ? .unavailable("No synthetic document supplied") : .ready,
                       action: empty ? nil : { count += 1 })
            Text("Synthetic callback count: \(count)").font(.caption)
            if !empty { ExportCard(name: "Synthetic pending document", readiness: .pending("Caller reports preparation pending")) }
        }
    }
}
#Preview("ExportCard · matrix") {
    PreviewMatrix("ExportCard") { ExportExample(empty: $0.isEmpty) }
}
#Preview("Provenance · matrix") {
    PreviewMatrix("Provenance") { scenario in
        Provenance(fact: scenario.isEmpty ? "" : "Synthetic extracted statement", sourceText: scenario.isEmpty ? nil : "Synthetic source text, shown in full when expanded.",
                   timestamp: scenario.isEmpty ? nil : Date(timeIntervalSince1970: 600), confidence: scenario.isEmpty ? nil : 0.99,
                   verification: .unreviewed)
    }
}
#endif
