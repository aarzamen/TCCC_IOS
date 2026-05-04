import SwiftUI

/// Encounter summary line for Screen 05 (Handoff), Column 1.
///
/// Layout per design brief §5.5:
///   3-col grid · 14pt icon · 90pt label (10pt) · flex value (13pt sans 500/600).
///   `isHot` lines tint with `palette.accentHot` and bump the value to weight 600.
struct SumLineView: View {
    let icon: String      // SF Symbol name
    let label: String     // e.g. "MOI", "CRITICAL", "TQ"
    let value: String
    let isHot: Bool

    @Environment(\.palette) private var palette

    init(icon: String, label: String, value: String, isHot: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.isHot = isHot
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHot ? palette.accentHot : palette.fg2)
                .frame(width: 14, alignment: .center)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(isHot ? palette.accentHot : palette.fg2)
                .textCase(.uppercase)
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: isHot ? .semibold : .medium))
                .foregroundStyle(isHot ? palette.accentHot : palette.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHot ? palette.accentDim.opacity(0.18) : Color.clear)
    }
}
