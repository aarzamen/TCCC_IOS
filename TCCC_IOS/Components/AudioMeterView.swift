import SwiftUI

struct AudioMeterView: View {
    let levels: AudioLevels
    let isActive: Bool

    @Environment(\.palette) private var palette

    private let barCount = AudioLevels.barCount
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 24

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let value = levels.bars[index]
                let height = max(2, CGFloat(value) * maxBarHeight)
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.bg2)
                        .frame(width: barWidth, height: maxBarHeight)
                    Rectangle()
                        .fill(barColor(at: index))
                        .frame(width: barWidth, height: height)
                }
                .frame(height: maxBarHeight)
                .opacity(isActive ? 1.0 : 0.35)
            }
        }
        .animation(.linear(duration: 0.05), value: levels.current)
    }

    private func barColor(at index: Int) -> Color {
        index >= barCount - 4 ? palette.accentHot : palette.accent
    }
}
