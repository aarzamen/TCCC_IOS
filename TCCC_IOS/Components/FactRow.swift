import SwiftUI

struct FactRow: View {
    let fact: ExtractedFact

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fact.kind.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(fact.kind.isHot ? palette.accent : palette.fg2)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(fact.kind.label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.fg2)
                Text(fact.value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.fg)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(timestamp)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.fg3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(fact.kind.isHot ? palette.bg2 : Color.clear)
    }

    private var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: fact.timestamp)
    }
}
