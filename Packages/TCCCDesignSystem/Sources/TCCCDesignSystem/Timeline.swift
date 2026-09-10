import SwiftUI

public struct TimelineEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let title: String
    public let detail: String?
    public let tone: SemanticRole
    public init(id: String, timestamp: Date, title: String, detail: String? = nil, tone: SemanticRole = .ink) {
        self.id = id; self.timestamp = timestamp; self.title = title; self.detail = detail; self.tone = tone
    }
}

enum TimelineSelection {
    /// Caller IDs should be unique. The first occurrence wins if the caller repeats an ID.
    static func events(_ events: [TimelineEvent]) -> [TimelineEvent] {
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }
    static func selectedID(_ id: String?, in events: [TimelineEvent]) -> String? {
        if let id, events.contains(where: { $0.id == id }) { return id }
        return events.first?.id
    }
}

/// Horizontal event navigation with stable caller IDs and full expandable detail.
/// Supply unique IDs; the first occurrence is shown if an ID is repeated.
public struct Timeline: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @State private var selectedID: String?
    @State private var showsDetail = true
    private let events: [TimelineEvent]
    private let timeZone: TimeZone

    public init(events: [TimelineEvent], timeZone: TimeZone = .gmt) {
        self.events = events; self.timeZone = timeZone
    }

    public var body: some View {
        let entries = TimelineSelection.events(events)
        let selection = TimelineSelection.selectedID(selectedID, in: entries)
        let index = entries.firstIndex { $0.id == selection }
        VStack(alignment: .leading, spacing: 12) {
            if entries.isEmpty {
                Text("No events recorded").foregroundStyle(theme.color(.muted)).frame(minHeight: metrics.row)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(entries) { event in
                                eventButton(event, selected: event.id == selection).id(event.id)
                            }
                        }.padding(4)
                    }
                    .onChange(of: selection) { _, value in
                        if let value { proxy.scrollTo(value, anchor: .center) }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { navigation(entries, index: index) }
                    VStack(alignment: .leading) { navigation(entries, index: index) }
                }
                if let index {
                    let event = entries[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title).font(.headline).foregroundStyle(theme.color(event.tone))
                        Text(DataDisplay.date(event.timestamp, timeZone: timeZone)).font(.caption.monospaced())
                        ActionButton(showsDetail ? "Hide event details" : "Show event details", variant: .ghost,
                                     systemImage: showsDetail ? "chevron.up" : "chevron.down") { showsDetail.toggle() }
                        if showsDetail { Text(event.detail ?? "No additional detail supplied").fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.palette.panel2.color, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .leading) { Rectangle().fill(theme.color(event.tone)).frame(width: 3) }
                }
            }
        }
        .padding(14).foregroundStyle(theme.color(.ink))
        .onChange(of: events) { _, _ in selectedID = TimelineSelection.selectedID(selectedID, in: TimelineSelection.events(events)) }
    }

    private func eventButton(_ event: TimelineEvent, selected: Bool) -> some View {
        Button { selectedID = event.id; showsDetail = true } label: {
            VStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle.fill").foregroundStyle(theme.color(event.tone))
                Text(event.title).font(.subheadline.weight(.semibold))
                Text(DataDisplay.date(event.timestamp, timeZone: timeZone)).font(.caption.monospaced())
            }
            .fixedSize(horizontal: false, vertical: true).padding(12)
            .frame(minWidth: metrics.tap, idealWidth: 180 * metrics.scale, maxWidth: 220 * metrics.scale, minHeight: metrics.tap)
            .background(selected ? theme.palette.panel2.color : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.color(event.tone) : theme.palette.line.color) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(event.title), \(DataDisplay.date(event.timestamp, timeZone: timeZone))")
        .accessibilityHint("Select event and show its details")
    }

    @ViewBuilder private func navigation(_ entries: [TimelineEvent], index: Int?) -> some View {
        ActionButton("Previous event", variant: .ghost, systemImage: "chevron.left", isEnabled: (index ?? 0) > 0,
                     disabledReason: "At first event") {
            if let index, index > 0 { selectedID = entries[index - 1].id; showsDetail = true }
        }
        ActionButton("Next event", variant: .ghost, systemImage: "chevron.right", isEnabled: (index ?? 0) < entries.count - 1,
                     disabledReason: "At last event") {
            if let index, index + 1 < entries.count { selectedID = entries[index + 1].id; showsDetail = true }
        }
    }
}

#if DEBUG
private struct TimelineExample: View {
    @State private var events: [TimelineEvent]
    init(empty: Bool) {
        _events = State(initialValue: empty ? [] : [
            TimelineEvent(id: "1", timestamp: Date(timeIntervalSince1970: 600), title: "Synthetic note", detail: "Example source text remains fully readable.", tone: .ai),
            TimelineEvent(id: "2", timestamp: Date(timeIntervalSince1970: 900), title: "Synthetic review", detail: "Caller-supplied status; no automatic verification.", tone: .warn)
        ])
    }
    var body: some View {
        VStack {
            Timeline(events: events)
            ActionButton("Remove synthetic events", isEnabled: !events.isEmpty, disabledReason: "No synthetic events") { events = [] }
        }
    }
}
#Preview("Timeline · matrix") {
    PreviewMatrix("Timeline") { TimelineExample(empty: $0.isEmpty) }
}
#endif
