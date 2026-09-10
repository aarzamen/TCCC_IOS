#if DEBUG
import SwiftUI

public enum PreviewScenario: String, CaseIterable, Identifiable, Sendable {
    case empty, populated, night, gloveAccessibility
    public var id: String { rawValue }
    public var isEmpty: Bool { self == .empty }
    public var title: String {
        switch self {
        case .empty: "Empty"
        case .populated: "Populated"
        case .night: "Night"
        case .gloveAccessibility: "Glove + large text"
        }
    }
    public var theme: Theme {
        switch self {
        case .night: .night
        case .gloveAccessibility: Theme.base.withGloveMode()
        default: .base
        }
    }
}

/// Preview-only presentation support. Every section is explicitly synthetic.
public struct PreviewMatrix<Content: View>: View {
    private let title: String
    private let content: (PreviewScenario) -> Content
    public init(_ title: String, @ViewBuilder content: @escaping (PreviewScenario) -> Content) {
        self.title = title
        self.content = content
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(PreviewScenario.allCases) { scenario in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SYNTHETIC PREVIEW · \(title) · \(scenario.title)")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(scenario.theme.color(.accent))
                            .accessibilityAddTraits(.isHeader)
                        content(scenario)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(scenario.theme.palette.background.color)
                    .environment(\.tcccTheme, scenario.theme)
                    .environment(\.dynamicTypeSize, scenario == .gloveAccessibility ? .accessibility3 : .large)
                }
            }
            .padding(12)
        }
        .background(Theme.base.palette.background.color)
        .preferredColorScheme(.dark)
    }
}

private struct ThemeExample: View {
    let scenario: PreviewScenario
    @State private var night: Bool
    @State private var glove: Bool
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    init(scenario: PreviewScenario) {
        self.scenario = scenario
        _night = State(initialValue: scenario == .night)
        _glove = State(initialValue: scenario == .gloveAccessibility)
    }
    private var selectedTheme: Theme { (night ? Theme.night : .base).withGloveMode(glove) }
    private var tap: CGFloat { ThemeMetrics(gloveMode: glove, scale: scale).tap }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Preview night palette", isOn: $night)
                .frame(minHeight: tap)
            Toggle("Preview glove targets", isOn: $glove)
                .frame(minHeight: tap)
            if scenario.isEmpty {
                Row("Example value")
            } else {
                ForEach(SemanticRole.allCases, id: \.self) { role in
                    HStack(spacing: 10) {
                        Circle().fill(selectedTheme.color(role)).frame(width: 18, height: 18)
                        Text(role.rawValue).foregroundStyle(selectedTheme.color(role)).font(.body.monospaced())
                    }
                }
            }
            ActionButton("Example action", variant: .navigate) { }
        }
        .foregroundStyle(selectedTheme.color(.ink))
        .environment(\.tcccTheme, selectedTheme)
    }
}

private struct ButtonsExample: View {
    let scenario: PreviewScenario
    @State private var count = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic action count: \(count)").foregroundStyle(scenario.theme.color(.ink))
            if scenario.isEmpty {
                ActionButton("No action available", variant: .neutral)
            } else {
                ForEach(ActionButtonVariant.allCases, id: \.self) { variant in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(ActionButtonSize.allCases, id: \.self) { size in
                            ActionButton("\(variant.rawValue.capitalized) · \(size.rawValue)", variant: variant,
                                         size: size, systemImage: "plus", fullWidth: true) { count += 1 }
                        }
                    }
                }
                ActionButton("Disabled example", isEnabled: false, disabledReason: "Example is intentionally disabled") { count += 1 }
            }
        }
    }
}

private struct SegmentedExample: View {
    let scenario: PreviewScenario
    @State private var selection = "review"
    private var options: [SegmentOption<String>] {
        scenario.isEmpty ? [] : [
            SegmentOption(value: "review", label: "Review", subtitle: "Caller-supplied status", tone: .warn),
            SegmentOption(value: "draft", label: "Draft", tone: .ai),
            SegmentOption(value: "ready", label: "Ready", tone: .ok)
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Segmented(options: options, selection: $selection, label: "Synthetic selection")
            Text("Selection: \(selection)").font(.body.monospaced()).foregroundStyle(scenario.theme.color(.ink))
        }
    }
}

#Preview("Theme · matrix") {
    PreviewMatrix("Theme") { ThemeExample(scenario: $0) }
}

#Preview("Panel · matrix") {
    PreviewMatrix("Panel") { scenario in
        Panel(title: "Synthetic panel", right: scenario.isEmpty ? nil : "Example") {
            Row("Casualty", value: scenario.isEmpty ? nil : "SYNTHETIC C-04")
        }
        Panel {
            Text("Untitled panel example").padding(14).foregroundStyle(scenario.theme.color(.ink))
        }
    }
}

#Preview("SectionHeader · matrix") {
    PreviewMatrix("SectionHeader") { scenario in
        SectionHeader("Synthetic section", right: scenario.isEmpty ? nil : "Caller supplied detail")
    }
}

#Preview("Row · matrix") {
    PreviewMatrix("Row") { scenario in
        VStack(spacing: 0) {
            Row("Casualty", value: scenario.isEmpty ? nil : "SYNTHETIC C-04")
            Row("Long example", value: scenario.isEmpty ? nil : "Synthetic text remains completely available as the layout grows at large text sizes.", tone: .ai)
            Row("Always missing example", value: nil)
        }
    }
}

#Preview("Pill · matrix") {
    PreviewMatrix("Pill") { scenario in
        VStack(alignment: .leading, spacing: 12) {
            if scenario.isEmpty { Pill(state: .none) }
            else {
                ForEach(PillState.allCases, id: \.self) { Pill(state: $0) }
                Pill(state: .pending, text: "Synthetic detail supplied by caller")
            }
        }
    }
}

#Preview("ActionButton · matrix") {
    PreviewMatrix("ActionButton") { ButtonsExample(scenario: $0) }
}

#Preview("Segmented · matrix") {
    PreviewMatrix("Segmented") { SegmentedExample(scenario: $0) }
}

#endif
