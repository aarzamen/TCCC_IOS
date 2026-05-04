import SwiftUI

/// Vertical-timeline row for Screen 05 (Handoff), Column 2.
///
/// Layout per design brief §5.5:
///   3-col grid · 54pt timestamp · 16pt rail · 1fr label/detail.
///   The middle column draws a vertical hairline from the top of the row to
///   the bottom (skipped on the last row) and a 9pt × 9pt square node centred
///   on the label baseline. Hot events fill the node with `palette.accent`,
///   non-hot use a 1.5px border with the panel background filled.
struct TimelineRow: View {
    let timestamp: String  // "14:24"
    let icon: String
    let kindLabel: String  // "TQ", "MED", "9L", etc.
    let detail: String
    let isHot: Bool
    let isLast: Bool

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Column 1 — timestamp
            Text(timestamp)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg2)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 6)

            // Column 2 — rail + node, fixed 16pt wide
            ZStack(alignment: .top) {
                // Vertical hairline stretches the full row; clipped under
                // the node. `isLast` skips the trailing run.
                if !isLast {
                    Rectangle()
                        .fill(palette.line)
                        .frame(width: Layout.hairline)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 6 + 9 / 2 + 1)
                } else {
                    // Half-line up to the node centre so this row still
                    // connects from above on a multi-row column.
                    Rectangle()
                        .fill(palette.line)
                        .frame(width: Layout.hairline, height: 6 + 9 / 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                // Node
                node
                    .padding(.top, 6)
            }
            .frame(width: 16)

            // Column 3 — label + detail, flex
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHot ? palette.accent : palette.fg2)
                    Text(kindLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(isHot ? palette.accent : palette.fg2)
                        .textCase(.uppercase)
                }
                Text(detail)
                    .font(.system(size: 13, weight: isHot ? .semibold : .medium))
                    .foregroundStyle(palette.fg)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var node: some View {
        if isHot {
            Rectangle()
                .fill(palette.accent)
                .frame(width: 9, height: 9)
        } else {
            Rectangle()
                .fill(palette.bg1)
                .frame(width: 9, height: 9)
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.fg2, lineWidth: 1.5)
                )
        }
    }
}
