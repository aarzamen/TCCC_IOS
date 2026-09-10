import SwiftUI

/// The same contact remains latched after cancellation or completion until release.
/// Generation fencing prevents a delayed task from completing a different hold.
struct HoldState {
    private(set) var generation: UInt64 = 0
    private(set) var contact = false
    private(set) var startedAt: TimeInterval?
    private(set) var fired = false

    mutating func begin(at time: TimeInterval) -> UInt64? {
        guard !contact else { return nil }
        generation &+= 1
        contact = true
        startedAt = time
        fired = false
        return generation
    }
    mutating func cancel() {
        generation &+= 1
        startedAt = nil
        fired = false
    }
    mutating func release() {
        cancel()
        contact = false
    }
    mutating func complete(generation candidate: UInt64, isPressed: Bool) -> Bool {
        guard isPressed, contact, startedAt != nil, !fired, candidate == generation else { return false }
        fired = true
        return true
    }
    func progress(at time: TimeInterval, duration: TimeInterval) -> Double {
        guard let startedAt, duration.isFinite, duration > 0 else { return 0 }
        if fired { return 1 }
        return min(1, max(0, (time - startedAt) / duration))
    }
}

/// A deliberate hold with a native progress ring. The alternate button opens an
/// explicit confirmation dialog for VoiceOver, Switch Control and keyboard users.
/// Callback acceptance does not imply the caller's operation succeeded.
public struct HoldToConfirm: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.scenePhase) private var scenePhase
    @DesignMetrics private var metrics
    @GestureState private var isPressed = false
    @State private var hold = HoldState()
    @State private var pending: Task<Void, Never>?
    @State private var showConfirmation = false
    @State private var acceptedCount = 0
    @State private var accepted = false
    private let title: String
    private let duration: TimeInterval
    private let systemImage: String
    private let confirmationTitle: String
    private let isEnabled: Bool
    private let disabledReason: String
    private let action: (() -> Void)?

    public init(_ title: String, duration: TimeInterval = 0.9,
                systemImage: String = "hand.tap", confirmationTitle: String? = nil,
                isEnabled: Bool = true, disabledReason: String = "Action unavailable",
                action: (() -> Void)? = nil) {
        self.title = title
        self.duration = duration.isFinite && duration > 0 ? max(0.3, duration) : 0.9
        self.systemImage = systemImage
        self.confirmationTitle = confirmationTitle ?? "Confirm \(title)"
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.action = action
    }
    private var enabled: Bool { isEnabled && environmentEnabled && action != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hold.startedAt == nil || hold.fired)) { _ in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(theme.color(.danger).opacity(0.3), lineWidth: 3)
                        Circle().trim(from: 0, to: hold.progress(at: ProcessInfo.processInfo.systemUptime, duration: duration))
                            .stroke(theme.color(.danger), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: hold.fired ? "checkmark" : systemImage).font(.caption.bold())
                    }
                    .frame(width: 30, height: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.body.weight(.semibold))
                        Text(hold.fired ? "Confirmation accepted" : "Hold to confirm · \(duration, specifier: "%.1f") s")
                            .font(.caption.monospaced())
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(minWidth: metrics.tap, minHeight: metrics.tap)
                .foregroundStyle(theme.color(enabled ? .danger : .muted))
                .background(theme.color(.danger).opacity(hold.fired ? 0.2 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.color(.danger), lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
                .onChanged { value in
                    guard enabled, scenePhase == .active else { cancelHold(); return }
                    guard hypot(value.translation.width, value.translation.height) <= 16 else { cancelHold(); return }
                    beginHold()
                }
                .onEnded { _ in releaseHold() })
            .accessibilityRepresentation {
                Button(title) { requestConfirmation() }
                    .accessibilityValue(hold.fired || accepted ? "Confirmation accepted" : (hold.startedAt == nil ? "Ready" : "Holding"))
                    .accessibilityHint("Opens a confirmation dialog")
                    .disabled(!enabled)
            }
            ActionButton("\(title), confirm with dialog", variant: .ghost,
                         isEnabled: enabled, disabledReason: disabledReason) { requestConfirmation() }
            if accepted && enabled {
                Text("Confirmation accepted").font(.caption).foregroundStyle(theme.color(.ink))
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(confirmationTitle, role: .destructive) {
                guard enabled, scenePhase == .active else { return }
                cancelHold()
                accept()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Confirm this action explicitly, or cancel to return.")
        }
        .sensoryFeedback(.success, trigger: acceptedCount)
        .onChange(of: isPressed) { _, pressed in if !pressed { releaseHold() } }
        .onChange(of: enabled) { _, value in
            if !value { cancelHold(); showConfirmation = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelHold(); showConfirmation = false }
        }
        .onDisappear { releaseHold(); showConfirmation = false }
    }
    private func beginHold() {
        guard let generation = hold.begin(at: ProcessInfo.processInfo.systemUptime) else { return }
        accepted = false
        pending?.cancel()
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard !Task.isCancelled, enabled, scenePhase == .active,
                  hold.complete(generation: generation, isPressed: isPressed) else { return }
            accept()
        }
    }
    private func cancelHold() { pending?.cancel(); pending = nil; hold.cancel() }
    private func releaseHold() { pending?.cancel(); pending = nil; hold.release() }
    private func requestConfirmation() {
        guard enabled, scenePhase == .active else { return }
        cancelHold()
        showConfirmation = true
    }
    private func accept() { accepted = true; acceptedCount += 1; action?() }
}

enum StatusTime {
    static func elapsed(startedAt: Date?, now: Date) -> String {
        guard let startedAt else { return "Unknown" }
        let interval = now.timeIntervalSince(startedAt)
        guard interval.isFinite, interval < Double(Int.max) else { return "Unknown" }
        let seconds = Int(max(0, interval))
        return String(format: "%02ld:%02ld:%02ld", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    static func zulu(_ now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss'Z'"
        return formatter.string(from: now)
    }
    static func local(_ now: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss 'GMT'Z"
        return "\(formatter.string(from: now)) · \(timeZone.identifier)"
    }
}

/// Live clock and core casualty identity (Unknown when absent). Optional metadata
/// remains absent unless supplied by the caller.
public struct StatusStrip: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    private let id: String?
    private let mgrs: String?
    private let gpsAccuracyMeters: Double?
    private let batteryFraction: Double?
    private let connectionStatus: String?
    private let page: Int?
    private let pages: Int?
    private let startedAt: Date?
    private let timeZone: TimeZone

    public init(id: String? = nil, mgrs: String? = nil, gpsAccuracyMeters: Double? = nil,
                batteryFraction: Double? = nil, connectionStatus: String? = nil,
                page: Int? = nil, pages: Int? = nil, startedAt: Date? = nil,
                timeZone: TimeZone = .autoupdatingCurrent) {
        self.id = id; self.mgrs = mgrs; self.gpsAccuracyMeters = gpsAccuracyMeters
        self.batteryFraction = batteryFraction; self.connectionStatus = connectionStatus
        self.page = page; self.pages = pages; self.startedAt = startedAt; self.timeZone = timeZone
    }
    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160 * metrics.scale), alignment: .leading)], alignment: .leading, spacing: 14) {
                cell("Zulu · UTC", StatusTime.zulu(context.date))
                cell("Local", StatusTime.local(context.date, timeZone: timeZone))
                cell("Elapsed", StatusTime.elapsed(startedAt: startedAt, now: context.date))
                cell("Casualty", clean(id))
                if let connectionStatus { cell("Connection · caller supplied", clean(connectionStatus)) }
                if let mgrs { cell("MGRS", clean(mgrs)) }
                if let accuracy = gpsAccuracyMeters {
                    cell("GPS accuracy", accuracy.isFinite && accuracy >= 0 ? "±\(accuracy.formatted()) m" : "Unknown")
                }
                if let battery = batteryFraction {
                    cell("Battery", battery.isFinite && (0...1).contains(battery) ? "\(Int((battery * 100).rounded()))%" : "Unknown")
                }
                if let page, let pages {
                    cell("Page", pages > 0 && (1...pages).contains(page) ? "\(page) of \(pages)" : "Unknown")
                }
            }
            .padding(12)
        }
        .background(theme.palette.background.color)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
    }
    private func clean(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Unknown" }
        return value
    }
    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(theme.color(.muted))
            Text(value).font(.body.monospaced()).foregroundStyle(theme.color(.ink))
        }
        .frame(minHeight: metrics.tap, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ScrollEdges: Equatable {
    var top: Bool
    var bottom: Bool
    init(top: Bool, bottom: Bool) { self.top = top; self.bottom = bottom }
    init(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        guard offset.isFinite, contentHeight.isFinite, viewportHeight.isFinite,
              viewportHeight > 0, contentHeight > viewportHeight else {
            self.init(top: false, bottom: false); return
        }
        self.init(top: offset > 1, bottom: offset + viewportHeight < contentHeight - 1)
    }
}

enum ScrollViewport {
    static func height(requested: CGFloat, metrics: ThemeMetrics) -> CGFloat {
        let baseHeight = requested.isFinite ? max(0, requested) : 200
        return max(metrics.tap, baseHeight * metrics.scale)
    }
}

/// A vertical scroll region whose mask changes with live content/viewport geometry.
public struct ScrollFade<Content: View>: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @State private var edges = ScrollEdges(top: false, bottom: false)
    private let requestedHeight: CGFloat
    private let content: Content
    private var height: CGFloat { ScrollViewport.height(requested: requestedHeight, metrics: metrics) }
    public init(height: CGFloat = 200, @ViewBuilder content: () -> Content) {
        self.requestedHeight = height
        self.content = content()
    }
    public var body: some View {
        ScrollView(.vertical) { content.frame(maxWidth: .infinity, alignment: .leading) }
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                ScrollEdges(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                            contentHeight: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom,
                            viewportHeight: geometry.containerSize.height)
            } action: { _, newEdges in edges = newEdges }
            .frame(height: height)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [edges.top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: min(28, height / 3))
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, edges.bottom ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: min(28, height / 3))
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if edges.bottom {
                    Text("more ↓").font(.caption.monospaced()).foregroundStyle(theme.color(.accent))
                        .padding(6).background(theme.palette.panel.color.opacity(0.9))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

public enum AssessmentState: String, CaseIterable, Sendable {
    case none, clear, done
    public var next: Self { switch self { case .none: .clear; case .clear: .done; case .done: .none } }
    public var title: String { switch self { case .none: "Not assessed"; case .clear: "Clear"; case .done: "Intervention" } }
    public var tone: SemanticRole { switch self { case .none: .muted; case .clear: .ok; case .done: .accent } }
    public var systemImage: String { switch self { case .none: "circle"; case .clear: "checkmark.circle"; case .done: "plus.circle.fill" } }
}

/// Whole-row cycle; assessment is owned by the caller, never derived from other data.
public struct AssessRow: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @Binding private var state: AssessmentState
    private let letter: String
    private let label: String
    private let note: String?
    public init(letter: String, label: String, state: Binding<AssessmentState>, note: String? = nil) {
        self.letter = letter; self.label = label; self._state = state; self.note = note
    }
    private var detail: String {
        if state == .done, let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return note }
        return state.title
    }
    public var body: some View {
        Button { state = state.next } label: {
            HStack(spacing: 14) {
                Text(letter).font(.title2.monospaced().bold()).foregroundStyle(theme.color(.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.body).foregroundStyle(theme.color(.muted))
                    Text(detail).font(.body.monospaced()).foregroundStyle(theme.color(state == .none ? .muted : .ink))
                }
                Spacer(minLength: 0)
                Image(systemName: state.systemImage).font(.title2).foregroundStyle(theme.color(state.tone)).accessibilityHidden(true)
            }
            .padding(14).padding(.leading, 4)
            .frame(maxWidth: .infinity, minHeight: metrics.row, alignment: .leading)
            .background(alignment: .leading) { Rectangle().fill(theme.color(state.tone)).frame(width: 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
        .accessibilityLabel("\(letter), \(label)")
        .accessibilityValue("\(state.title)\(detail == state.title ? "" : ", \(detail)")")
        .accessibilityHint("Changes to \(state.next.title)")
    }
}

#if DEBUG
private struct HoldExample: View {
    let scenario: PreviewScenario
    @State private var count = 0
    var body: some View {
        VStack(alignment: .leading) {
            HoldToConfirm("Synthetic action", isEnabled: !scenario.isEmpty, disabledReason: "No example action supplied") { count += 1 }
            Text("Synthetic confirmation count: \(count)").foregroundStyle(scenario.theme.color(.ink))
        }
    }
}
private struct AssessExample: View {
    let scenario: PreviewScenario
    @State private var first: AssessmentState = .none
    @State private var second: AssessmentState = .none
    var body: some View {
        VStack(spacing: 0) {
            AssessRow(letter: "A", label: "Synthetic assessment A", state: $first, note: "Synthetic caller-supplied intervention detail with full wrapping text")
            AssessRow(letter: "B", label: "Synthetic assessment B", state: $second)
        }
        .onAppear { if !scenario.isEmpty { first = .done; second = .clear } }
    }
}
private struct ScrollExample: View {
    let scenario: PreviewScenario
    @State private var extra = 0
    var body: some View {
        VStack {
            ActionButton("Add synthetic row") { extra += 1 }
            ScrollFade(height: 220) {
                VStack(alignment: .leading, spacing: 18) {
                    if scenario.isEmpty && extra == 0 { Text("No example content").foregroundStyle(scenario.theme.color(.muted)) }
                    ForEach(0..<(scenario.isEmpty ? extra : 8 + extra), id: \.self) { index in
                        Row("Synthetic row \(index + 1)", value: "Example content that can grow and scroll")
                    }
                }
            }
        }
    }
}
#Preview("HoldToConfirm · matrix") { PreviewMatrix("HoldToConfirm") { HoldExample(scenario: $0) } }
#Preview("StatusStrip · matrix") {
    PreviewMatrix("StatusStrip") { scenario in
        StatusStrip(id: scenario.isEmpty ? nil : "SYNTHETIC C-04", mgrs: scenario.isEmpty ? nil : "SYNTHETIC GRID — NOT A LOCATION",
                    gpsAccuracyMeters: scenario.isEmpty ? nil : 12, batteryFraction: scenario.isEmpty ? nil : 0.31,
                    connectionStatus: scenario.isEmpty ? nil : "Synthetic offline state", page: scenario.isEmpty ? nil : 3,
                    pages: scenario.isEmpty ? nil : 5, startedAt: scenario.isEmpty ? nil : Date.now.addingTimeInterval(-90_061))
    }
}
#Preview("ScrollFade · matrix") { PreviewMatrix("ScrollFade") { ScrollExample(scenario: $0) } }
#Preview("AssessRow · matrix") { PreviewMatrix("AssessRow") { AssessExample(scenario: $0) } }
#endif
