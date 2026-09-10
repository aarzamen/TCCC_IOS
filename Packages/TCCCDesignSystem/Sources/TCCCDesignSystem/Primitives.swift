import SwiftUI

public struct SectionHeader: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    private let title: String
    private let right: String?

    public init(_ title: String, right: String? = nil) {
        self.title = title
        self.right = right
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title).font(.headline).foregroundStyle(theme.color(.ink))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let right, !right.isEmpty {
                Text(right).font(.caption.monospaced()).foregroundStyle(theme.color(.accent))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
    }
}

public struct Panel<Content: View>: View {
    @Environment(\.tcccTheme) private var theme
    private let title: String?
    private let right: String?
    private let content: Content

    public init(title: String? = nil, right: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.right = right
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, !title.isEmpty { SectionHeader(title, right: right) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.panel.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.line.color, lineWidth: 1) }
    }
}

public struct Row: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @DesignMetrics private var metrics
    private let label: String
    private let value: String?
    private let empty: String
    private let tone: SemanticRole

    public init(_ label: String, value: String? = nil, empty: String = "Unknown — not recorded", tone: SemanticRole = .ink) {
        self.label = label
        self.value = value
        self.empty = empty
        self.tone = tone
    }

    private var hasValue: Bool { !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    private var displayedValue: String { hasValue ? value! : empty }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(label).font(.subheadline).foregroundStyle(theme.color(.muted))
            Text(displayedValue).font(.body.monospaced())
                .foregroundStyle(theme.color(hasValue ? tone : .muted))
                .italic(!hasValue)
                .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: metrics.row)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue(displayedValue)
    }
}

public enum PillState: String, CaseIterable, Sendable {
    case ready, pending, draft, offline, derived, none
    public var title: String {
        switch self {
        case .ready: "Ready"
        case .pending: "Pending"
        case .draft: "Draft"
        case .offline: "Offline"
        case .derived: "AI derived"
        case .none: "Not assessed"
        }
    }
    public var tone: SemanticRole {
        switch self {
        case .ready: .ok
        case .pending: .warn
        case .draft: .muted
        case .offline: .accent
        case .derived: .ai
        case .none: .muted
        }
    }
    public var systemImage: String {
        switch self {
        case .ready: "checkmark"
        case .pending: "exclamationmark.triangle"
        case .draft: "doc.text"
        case .offline: "wifi.slash"
        case .derived: "sparkles"
        case .none: "questionmark.circle"
        }
    }
}

/// Caller-supplied status, encoded in symbol, text and color. It performs no verification.
public struct Pill: View {
    @Environment(\.tcccTheme) private var theme
    private let state: PillState
    private let text: String?
    public init(state: PillState, text: String? = nil) {
        self.state = state
        self.text = text
    }
    public var body: some View {
        Label(text ?? state.title, systemImage: state.systemImage)
            .font(.caption.monospaced().weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(theme.color(state.tone))
            .background(theme.color(state.tone).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(theme.color(state.tone), lineWidth: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text == nil || text == state.title ? state.title : "\(state.title): \(text!)")
    }
}

public enum ActionButtonVariant: String, CaseIterable, Sendable {
    case navigate, ai, confirm, caution, danger, neutral, ghost
    public var tone: SemanticRole {
        switch self {
        case .navigate: .accent
        case .ai: .ai
        case .confirm: .ok
        case .caution: .warn
        case .danger: .danger
        case .neutral: .ink
        case .ghost: .muted
        }
    }
}

/// Styled native button. Destructive operations should use HoldToConfirm, not this primitive.
public struct ActionButton: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.isEnabled) private var environmentEnabled
    @DesignMetrics private var metrics
    private let title: String
    private let variant: ActionButtonVariant
    private let size: ActionButtonSize
    private let systemImage: String?
    private let isEnabled: Bool
    private let disabledReason: String?
    private let fullWidth: Bool
    private let action: (() -> Void)?

    public init(_ title: String, variant: ActionButtonVariant = .neutral, size: ActionButtonSize = .medium,
                systemImage: String? = nil, isEnabled: Bool = true, disabledReason: String? = nil,
                fullWidth: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.variant = variant
        self.size = size
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.fullWidth = fullWidth
        self.action = action
    }

    private var enabled: Bool { isEnabled && action != nil && environmentEnabled }
    private var filled: Bool { variant == .navigate || variant == .confirm }
    private var foreground: Color { filled ? Theme.base.palette.background.color : theme.color(variant.tone) }
    private var background: Color { filled ? theme.color(variant.tone) : (variant == .neutral ? theme.palette.panel2.color : .clear) }
    private var border: Color { variant == .ghost ? .clear : (variant == .neutral ? theme.palette.line.color : theme.color(variant.tone)) }
    private var reason: String { disabledReason ?? (action == nil ? "Unavailable — no action provided" : "Unavailable") }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SwiftUI.Button { action?() } label: {
                HStack(spacing: 8) {
                    if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
                .font((size == .small ? Font.subheadline : Font.body).weight(.semibold))
                .padding(.horizontal, size == .small ? 12 : 18).padding(.vertical, 8)
                .frame(minWidth: metrics.tap, maxWidth: fullWidth ? .infinity : nil, minHeight: metrics.buttonHeight(size))
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1.5) }
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.55)
            .accessibilityLabel(title).accessibilityHint(enabled ? "" : reason)
            if !enabled {
                Text(reason).font(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public struct SegmentOption<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    public let subtitle: String?
    public let tone: SemanticRole?
    public var id: Value { value }
    public init(value: Value, label: String, subtitle: String? = nil, tone: SemanticRole? = nil) {
        self.value = value
        self.label = label
        self.subtitle = subtitle
        self.tone = tone
    }
}

/// Adaptive native buttons retain their minimum targets instead of compressing segmented labels.
public struct Segmented<Value: Hashable>: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @DesignMetrics private var metrics
    @Binding private var selection: Value
    private let options: [SegmentOption<Value>]
    private let label: String

    public init(options: [SegmentOption<Value>], selection: Binding<Value>, label: String) {
        self.options = options
        _selection = selection
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(theme.color(.muted))
            if options.isEmpty {
                Text("No options available").font(.body).foregroundStyle(theme.color(.muted))
                    .frame(minHeight: metrics.tap)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: 8)], spacing: 8) {
                    ForEach(options) { option in
                        segment(option)
                    }
                }
            }
        }
        .padding(8)
        .background(theme.palette.panel.color, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.palette.line.color, lineWidth: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }

    private func segment(_ option: SegmentOption<Value>) -> some View {
        let selected = selection == option.value
        let tone = option.tone ?? .accent
        return SwiftUI.Button { selection = option.value } label: {
            HStack(spacing: 8) {
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label).font(.body.weight(.semibold))
                    if let subtitle = option.subtitle { Text(subtitle).font(.caption.monospaced()) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(minWidth: metrics.tap, maxWidth: .infinity, minHeight: metrics.tap)
            .foregroundStyle(selected ? Theme.base.palette.background.color : theme.color(tone))
            .background(selected ? theme.color(tone) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(theme.palette.line.color, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([option.label, option.subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}
