import SwiftUI

struct PlaybackLevelSnapshot: Equatable, Sendable {
    var samples: [Double]
    var averageLevel: Double
    var peakLevel: Double

    init(samples: [Double], averageLevel: Double, peakLevel: Double) {
        self.samples = samples.map(Self.clamp)
        self.averageLevel = Self.clamp(averageLevel)
        self.peakLevel = Self.clamp(peakLevel)
    }

    static func inactive(sampleCount: Int = 48) -> PlaybackLevelSnapshot {
        PlaybackLevelSnapshot(
            samples: Array(repeating: 0, count: sampleCount),
            averageLevel: 0,
            peakLevel: 0
        )
    }

    func appending(sample: Double, peak: Double, capacity: Int = 48) -> PlaybackLevelSnapshot {
        let targetCapacity = max(1, capacity)
        var nextSamples = samples
        nextSamples.append(Self.clamp(sample))
        if nextSamples.count > targetCapacity {
            nextSamples.removeFirst(nextSamples.count - targetCapacity)
        }
        if nextSamples.count < targetCapacity {
            nextSamples.insert(
                contentsOf: Array(repeating: 0, count: targetCapacity - nextSamples.count),
                at: 0
            )
        }

        return PlaybackLevelSnapshot(
            samples: nextSamples,
            averageLevel: sample,
            peakLevel: peak
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

struct PlaybackVisualizer: View {
    let snapshot: PlaybackLevelSnapshot
    let isActive: Bool

    @Environment(\.palette) private var palette

    init(snapshot: PlaybackLevelSnapshot = .inactive(), isActive: Bool = false) {
        self.snapshot = snapshot
        self.isActive = isActive
    }

    init(samples: [Double], isActive: Bool) {
        let clampedSamples = samples.map { min(1, max(0, $0.isFinite ? $0 : 0)) }
        let average = clampedSamples.last ?? 0
        let peak = clampedSamples.max() ?? 0
        self.snapshot = PlaybackLevelSnapshot(
            samples: clampedSamples.isEmpty ? PlaybackLevelSnapshot.inactive().samples : clampedSamples,
            averageLevel: average,
            peakLevel: peak
        )
        self.isActive = isActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            waveform
                .frame(height: 86)

            VStack(alignment: .leading, spacing: 6) {
                meterRow(label: "AVG", value: activeValue(snapshot.averageLevel))
                meterRow(label: "PK", value: activeValue(snapshot.peakLevel))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var waveform: some View {
        GeometryReader { proxy in
            let samples = normalizedSamples
            let barSpacing: CGFloat = 2
            let barCount = max(samples.count, 1)
            let rawWidth = (proxy.size.width - (CGFloat(barCount - 1) * barSpacing)) / CGFloat(barCount)
            let barWidth = max(2, rawWidth)
            let maxHeight = max(1, proxy.size.height - 4)

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(samples.indices, id: \.self) { index in
                    let value = samples[index]
                    let height = max(2, maxHeight * CGFloat(value))
                    Rectangle()
                        .fill(barColor(index: index, total: samples.count, value: value))
                        .frame(width: barWidth, height: height)
                        .opacity(isActive ? 1 : 0.34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(palette.bg)
            .overlay(
                Rectangle()
                    .strokeBorder(palette.line, lineWidth: Layout.hairline)
            )
        }
        .animation(.linear(duration: 0.05), value: snapshot)
    }

    private func meterRow(label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .tccc(.labelTiny)
                .foregroundStyle(palette.fg2)
                .frame(width: 30, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.bg2)
                    Rectangle()
                        .fill(value > 0.85 ? palette.warn : palette.accent)
                        .frame(width: proxy.size.width * CGFloat(value))
                }
                .overlay(
                    Rectangle()
                        .strokeBorder(palette.line, lineWidth: Layout.hairline)
                )
            }
            .frame(height: 12)

            Text("\(Int((value * 100).rounded()))%")
                .tccc(.meta)
                .foregroundStyle(value > 0.85 ? palette.warn : palette.fg1)
                .frame(width: 44, alignment: .trailing)
        }
        .frame(minHeight: 18)
    }

    private var normalizedSamples: [Double] {
        let samples = snapshot.samples.isEmpty
            ? PlaybackLevelSnapshot.inactive().samples
            : snapshot.samples
        return samples.map { isActive ? $0 : 0 }
    }

    private func activeValue(_ value: Double) -> Double {
        isActive ? value : 0
    }

    private func barColor(index: Int, total: Int, value: Double) -> Color {
        guard isActive else { return palette.fg3 }
        if value > 0.85 { return palette.warn }
        if index >= max(0, total - 8) { return palette.accentHot }
        return palette.accent
    }

    private var accessibilityLabel: String {
        if !isActive {
            return "Playback visualizer inactive, no audio level samples"
        }
        let average = Int((snapshot.averageLevel * 100).rounded())
        let peak = Int((snapshot.peakLevel * 100).rounded())
        return "Playback levels, average \(average) percent, peak \(peak) percent"
    }
}

#Preview {
    VStack(spacing: 20) {
        PlaybackVisualizer(
            snapshot: PlaybackLevelSnapshot(
                samples: [0, 0.1, 0.22, 0.5, 0.9, 0.35, 0.2, 0.05],
                averageLevel: 0.35,
                peakLevel: 0.9
            ),
            isActive: true
        )
        PlaybackVisualizer()
    }
    .padding()
    .background(Palette.dark.bg)
    .environment(\.palette, .dark)
}
