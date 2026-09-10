#if DEBUG
import SwiftUI

/// Synthetic composition only; excluded from release builds and never connected to app state.
public struct ComposedHandoff: View {
    private let scenario: PreviewScenario

    public init(scenario: PreviewScenario = .populated) {
        self.scenario = scenario
    }

    public var body: some View {
        HandoffPreviewContent(scenario: scenario)
            .environment(\.tcccTheme, scenario.theme)
            .transformEnvironment(\.dynamicTypeSize) { size in
                if scenario == .gloveAccessibility { size = .accessibility3 }
            }
            .preferredColorScheme(.dark)
    }
}

private struct HandoffPreviewContent: View {
    let scenario: PreviewScenario
    @Environment(\.tcccTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var startedAt = Date().addingTimeInterval(-2_700)
    @State private var feedback = "Demo controls report callbacks here. No clinical record or export is created."
    @State private var actionCount = 0

    private var encounterID: String? { scenario.isEmpty ? nil : "SYNTHETIC-01" }
    private var events: [TimelineEvent] {
        scenario.isEmpty ? [] : [
            TimelineEvent(id: "start", timestamp: startedAt, title: "Preview opened",
                          detail: "Synthetic layout fixture initialized. No patient information is supplied."),
            TimelineEvent(id: "note", timestamp: startedAt.addingTimeInterval(600), title: "Example note",
                          detail: "Neutral sample text for checking event navigation and text wrapping.", tone: .ai),
            TimelineEvent(id: "review", timestamp: startedAt.addingTimeInterval(1_200), title: "Review pending",
                          detail: "Synthetic review marker. No clinical facts have been verified.", tone: .warn)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SYNTHETIC PREVIEW · \(scenario.title)")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(theme.color(.accent))
                        .padding(14)
                        .accessibilityAddTraits(.isHeader)
                    StatusStrip(id: encounterID, page: 5, pages: 5,
                                startedAt: scenario.isEmpty ? nil : startedAt)
                    pageHeader
                    if geometry.size.width >= 760 && !typeSize.isAccessibilitySize {
                        let available = max(0, geometry.size.width - 36)
                        HStack(alignment: .top, spacing: 12) {
                            encounterColumn.frame(width: available * 0.6)
                            exports.frame(width: available * 0.4)
                        }
                        .padding(12)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            encounterColumn
                            exports
                        }
                        .padding(12)
                    }
                    Toolbar(previousTitle: "MEDEVAC", nextTitle: "Done",
                            onPrevious: { report("MEDEVAC navigation requested") },
                            onNext: { report("Done navigation requested") },
                            onSettings: { report("Settings requested") },
                            onNewCasualty: { report("New casualty requested; no record created") },
                            onEndCare: { report("End care requested; no care state changed") },
                            onWipe: { report("Wipe confirmation accepted; no data deleted") })
                    actionFeedback.padding(14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.palette.background.color)
            .foregroundStyle(theme.color(.ink))
        }
    }

    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                headerTitle
                Spacer(minLength: 0)
                Pill(state: .draft, text: "Preview only")
            }
            VStack(alignment: .leading, spacing: 10) {
                headerTitle
                Pill(state: .draft, text: "Preview only")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
    }

    private var headerTitle: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text("5 / 5").font(.subheadline.monospaced().weight(.bold)).foregroundStyle(theme.color(.accent))
            Text("Handoff").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("Role 1 to Role 2").font(.subheadline).foregroundStyle(theme.color(.muted))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var encounterColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Panel(title: "Timeline", right: scenario.isEmpty ? nil : "Synthetic events") {
                ScrollFade(height: 300) { Timeline(events: events) }
            }
            Panel(title: "Encounter summary", right: encounterID) {
                ScrollFade(height: 170) {
                    VStack(spacing: 0) {
                        Row("Encounter", value: encounterID)
                        Row("Source", value: scenario.isEmpty ? nil : "Synthetic layout fixture")
                        Row("Review", value: scenario.isEmpty ? nil : "Not reviewed", tone: .warn)
                        Row("Clinical findings")
                        Row("Last observations")
                        Row("Attachments", value: scenario.isEmpty ? nil : "None created")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) { summaryActions }
                    VStack(alignment: .leading, spacing: 8) { summaryActions }
                }
                .padding(12)
                actionFeedback.padding([.horizontal, .bottom], 12)
            }
        }
    }

    @ViewBuilder private var summaryActions: some View {
        ActionButton("Write narrative", variant: .ai, size: .small, systemImage: "sparkles",
                     isEnabled: !scenario.isEmpty, disabledReason: "No synthetic source text") {
            report("Narrative callback accepted; no narrative generated")
        }
        ActionButton("Confirm facts", variant: .confirm, size: .small, systemImage: "checkmark",
                     isEnabled: !scenario.isEmpty, disabledReason: "No synthetic facts to review") {
            report("Review callback accepted; no clinical facts verified")
        }
    }

    private var exports: some View {
        Panel(title: "Export and transmit") {
            ScrollFade(height: 470) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview only · no files or delivery services")
                        .font(.caption).foregroundStyle(theme.color(.muted))
                    ExportCard(name: "DD 1380 casualty card", systemImage: "doc.text",
                               metadata: "PDF", readiness: .unavailable("No PDF created in this preview"))
                    ExportCard(name: "Encounter JSON", systemImage: "curlybraces",
                               metadata: "Synthetic fixture", readiness: scenario.isEmpty
                               ? .unavailable("No encounter supplied")
                               : .pending("Example review pending; no JSON file created"))
                    ExportCard(name: "Audio, full recording", systemImage: "waveform",
                               readiness: .unavailable("No recording supplied"))
                    ActionButton("Show handoff QR", variant: .navigate, systemImage: "qrcode",
                                 isEnabled: !scenario.isEmpty, disabledReason: "No synthetic encounter supplied",
                                 fullWidth: true) {
                        report("QR callback accepted; no QR generated or delivered")
                    }
                    actionFeedback
                }
                .padding(12)
            }
        }
    }

    private var actionFeedback: some View {
        Text(feedback)
            .font(.caption.monospaced())
            .foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Synthetic action feedback")
            .accessibilityValue(feedback)
    }

    private func report(_ message: String) {
        actionCount += 1
        feedback = "Synthetic action \(actionCount): \(message)."
    }
}

#Preview("ComposedHandoff · Empty / Populated / Night / Glove") {
    PreviewMatrix("Composed handoff") { scenario in
        ComposedHandoff(scenario: scenario)
            .frame(height: 1_000)
    }
    .frame(width: 1_100, height: 1_000)
}
#endif
