import SwiftUI

struct TranscriptLineView: View {
    let line: TranscriptLine
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(speakerLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(speakerColor)
                Text(line.displayTimestamp)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.fg3)
            }
            .frame(width: 64, alignment: .leading)

            Text(line.text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(textColor)
                .italic(line.speaker == .system)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .opacity(line.isPartial ? 0.7 : 1.0)
        .overlay(alignment: .leading) {
            if line.isPartial {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2)
            }
        }
        .background(line.isPartial ? palette.bg2 : Color.clear)
    }

    private var speakerLabel: String {
        switch line.speaker {
        case .medic:    "MEDIC"
        case .casualty: "CASUALTY"
        case .system:   "SYSTEM"
        }
    }

    private var speakerColor: Color {
        switch line.speaker {
        case .medic:    palette.fg1
        case .casualty: palette.fg2
        case .system:   palette.accent
        }
    }

    private var textColor: Color {
        switch line.speaker {
        case .medic:    palette.fg
        case .casualty: palette.fg1
        case .system:   palette.accent
        }
    }
}
