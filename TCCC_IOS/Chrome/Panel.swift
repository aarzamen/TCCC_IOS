import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.
// `.playgroundEditable(_:hint:)` makes this panel discoverable to the
// design playground. The hooks compile to no-ops in release builds.
// If you find yourself removing them, ask why first.

struct Panel<Content: View>: View {
    let title: String
    let titleIcon: String?
    let action: String?
    let accent: Bool
    let padded: Bool
    /// Optional explicit ID — when set, this panel registers with the
    /// playground so its title / icon / borders / visibility are
    /// editable. Default `nil` for backwards compat with sites that
    /// haven't been wired up yet.
    let playgroundID: ElementID?
    @ViewBuilder let content: () -> Content

    @Environment(\.palette) private var palette
    @Environment(\.playgroundProvider) private var provider

    init(
        _ title: String,
        titleIcon: String? = nil,
        action: String? = nil,
        accent: Bool = false,
        padded: Bool = true,
        playgroundID: ElementID? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.titleIcon = titleIcon
        self.action = action
        self.accent = accent
        self.padded = padded
        self.playgroundID = playgroundID
        self.content = content
    }

    var body: some View {
        if let id = playgroundID, PlaygroundOverrides.isHidden(id, provider: provider) {
            EmptyView()
        } else {
            panelBody
                .modifier(OptionalEditable(id: playgroundID, hint: panelHint))
        }
    }

    private var panelHint: ElementHint {
        ElementHint(
            label: title,
            supports: [.visibility, .text, .icon, .frame, .edges]
        )
    }

    private var resolvedTitle: String {
        guard let id = playgroundID else { return title }
        return PlaygroundOverrides.string(id, default: title, provider: provider)
    }

    private var resolvedIcon: String? {
        guard let id = playgroundID else { return titleIcon }
        return PlaygroundOverrides.icon(id, default: titleIcon, provider: provider)
    }

    private var hiddenEdges: BorderEdges {
        guard let id = playgroundID else { return .none }
        return PlaygroundOverrides.hiddenEdges(id, provider: provider)
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padded ? Layout.panelPadding : 0)
        }
        .background(palette.bg1)
        .overlay(
            SidedBorder(hidden: hiddenEdges, lineWidth: Layout.hairline)
                .foregroundStyle(accent ? palette.accentDim : palette.line)
        )
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                if let icon = resolvedIcon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.fg)
                }
                Text(resolvedTitle)
                    .tccc(.labelSmall)
                    .foregroundStyle(palette.fg)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 0)

            if let action {
                Text(action)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(0.7)
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                    .textCase(.uppercase)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
    }
}

/// Apply `.playgroundEditable(_:)` only if an ID is provided. Lets
/// `Panel` defer the cost of registration when a caller hasn't named
/// the panel yet.
private struct OptionalEditable: ViewModifier {
    let id: ElementID?
    let hint: ElementHint

    func body(content: Content) -> some View {
        if let id {
            content.playgroundEditable(id, hint: hint)
        } else {
            content
        }
    }
}
