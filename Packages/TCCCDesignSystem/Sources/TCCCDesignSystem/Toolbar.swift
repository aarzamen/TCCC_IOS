import SwiftUI

/// Full-word caller actions. Destructive confirmation stays in a separate group.
public struct Toolbar: View {
    @Environment(\.tcccTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @DesignMetrics private var metrics
    private let previousTitle: String
    private let nextTitle: String
    private let onPrevious: (() -> Void)?
    private let onNext: (() -> Void)?
    private let onSettings: (() -> Void)?
    private let onNewCasualty: (() -> Void)?
    private let onEndCare: (() -> Void)?
    private let onWipe: (() -> Void)?

    public init(previousTitle: String = "Previous", nextTitle: String = "Next",
                onPrevious: (() -> Void)? = nil, onNext: (() -> Void)? = nil,
                onSettings: (() -> Void)? = nil, onNewCasualty: (() -> Void)? = nil,
                onEndCare: (() -> Void)? = nil, onWipe: (() -> Void)? = nil) {
        self.previousTitle = previousTitle; self.nextTitle = nextTitle
        self.onPrevious = onPrevious; self.onNext = onNext; self.onSettings = onSettings
        self.onNewCasualty = onNewCasualty; self.onEndCare = onEndCare; self.onWipe = onWipe
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? max(260, metrics.tap) : 160), alignment: .leading)],
                      alignment: .leading, spacing: 12) {
                ActionButton(previousTitle, variant: .ghost, systemImage: "chevron.left", disabledReason: "Previous navigation unavailable", fullWidth: true, action: onPrevious)
                ActionButton("New casualty", variant: .neutral, systemImage: "plus", disabledReason: "New casualty action unavailable", fullWidth: true, action: onNewCasualty)
                ActionButton("End care", variant: .neutral, systemImage: "checkmark.shield", disabledReason: "End care action unavailable", fullWidth: true, action: onEndCare)
                ActionButton("Settings", variant: .ghost, systemImage: "gearshape", disabledReason: "Settings unavailable", fullWidth: true, action: onSettings)
                ActionButton(nextTitle, variant: .navigate, systemImage: "chevron.right", disabledReason: "Next navigation unavailable", fullWidth: true, action: onNext)
            }
            Rectangle().fill(theme.palette.line.color).frame(height: 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Destructive action").font(.caption.weight(.semibold)).foregroundStyle(theme.color(.danger))
                HoldToConfirm("Wipe", duration: 3, systemImage: "trash", confirmationTitle: "Confirm wipe",
                              disabledReason: "Wipe action unavailable", action: onWipe)
            }
        }
        .padding(14).foregroundStyle(theme.color(.ink)).background(theme.palette.background.color)
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.line.color).frame(height: 1) }
    }
}

#if DEBUG
private struct ToolbarExample: View {
    let empty: Bool
    @State private var feedback = "No synthetic action yet"
    var body: some View {
        VStack(alignment: .leading) {
            Toolbar(previousTitle: "Previous", nextTitle: "Done",
                    onPrevious: empty ? nil : { feedback = "Synthetic previous callback" },
                    onNext: empty ? nil : { feedback = "Synthetic next callback" },
                    onSettings: empty ? nil : { feedback = "Synthetic settings callback" },
                    onNewCasualty: empty ? nil : { feedback = "Synthetic new casualty callback" },
                    onEndCare: empty ? nil : { feedback = "Synthetic end care callback" },
                    onWipe: empty ? nil : { feedback = "Synthetic wipe confirmation accepted" })
            Text(feedback).font(.caption)
        }
    }
}
#Preview("Toolbar · matrix") {
    PreviewMatrix("Toolbar") { ToolbarExample(empty: $0.isEmpty) }
}
#endif
