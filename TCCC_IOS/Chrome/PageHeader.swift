import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.

/// Compact single-line page header for landscape iPhone.
///
/// Replaces the design's stacked-column header (index above kicker above
/// title) with a single horizontal row to reclaim ~60pt of vertical space.
/// The full canvas on iPhone 17 Pro landscape is ~430pt — every pt saved
/// up here is one less pt the panels below have to fight for.
struct PageHeader: View {
    let screen: AppState.Screen
    let total: Int
    let trailingKickerLabel: String?
    let trailingKickerValue: String?

    @Environment(\.palette) private var palette
    @Environment(\.playgroundProvider) private var provider

    private var elementID: ElementID {
        ElementID.pageHeader(playgroundScreen)
    }

    private var playgroundScreen: ElementID.Screen {
        switch screen {
        case .liveCapture: .liveCapture
        case .vitals:      .vitals
        case .tcccCard:    .tcccCard
        case .medevac:     .medevac
        case .handoff:     .handoff
        }
    }

    private var resolvedTitle: String {
        PlaygroundOverrides.string(elementID, default: screen.title, provider: provider)
    }

    init(
        screen: AppState.Screen,
        total: Int,
        trailingKickerLabel: String? = nil,
        trailingKickerValue: String? = nil
    ) {
        self.screen = screen
        self.total = total
        self.trailingKickerLabel = trailingKickerLabel
        self.trailingKickerValue = trailingKickerValue
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            indexLabel
                .fixedSize(horizontal: true, vertical: false)

            Text(resolvedTitle)
                .font(.system(size: 16, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.fg)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(screen.kicker)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(palette.fg3)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            if let label = trailingKickerLabel, let value = trailingKickerValue {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(palette.fg1)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: Layout.pageHeaderHeight)
        .background(palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.line)
                .frame(height: Layout.hairline)
        }
        .playgroundEditable(
            elementID,
            hint: ElementHint(
                label: screen.title,
                supports: [.visibility, .text, .frame]
            )
        )
    }

    private var indexLabel: some View {
        Text(String(format: "%02d / %02d", screen.rawValue + 1, total))
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(0.8)
            .monospacedDigit()
            .foregroundStyle(palette.accent)
    }
}
