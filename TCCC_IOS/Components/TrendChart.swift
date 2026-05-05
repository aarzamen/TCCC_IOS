import SwiftUI
import TCCCDesign

// PLAYGROUND HOOK — see superplayground.md.

/// 15-minute trend plot for HR / BP-systolic / SpO₂.
///
/// Drawn into a `Canvas` (no Charts framework — full control over the tactical
/// theme). Three series are scaled to their own clinical ranges so each line
/// uses the full vertical range of the chart:
///   - HR     70..160  (palette.crit)
///   - BPs    60..140  (palette.warn)
///   - SpO₂   85..100  (palette.fg1)
///
/// Layout: 24pt internal padding, 4 dashed horizontal gridlines, x-axis labels
/// "−15m" → "NOW", legend top-left. Empty history renders a centred
/// "No trend yet" placeholder.
struct TrendChart: View {
    let history: VitalsHistory

    @Environment(\.palette) private var palette

    private let inset: CGFloat = 24
    private let leftInset: CGFloat = 32
    private let bottomInset: CGFloat = 26
    private let topInset: CGFloat = 24
    private let rightInset: CGFloat = 12

    private struct Series {
        let label: String
        let unit: String
        let min: Double
        let max: Double
        let value: (VitalsHistorySample) -> Double?
    }

    private var seriesList: [(Series, Color)] {
        [
            (Series(label: "HR",   unit: "bpm",  min: 70,  max: 160,
                    value: { $0.hr.map(Double.init) }),
             palette.crit),
            (Series(label: "BPs",  unit: "mmHg", min: 60,  max: 140,
                    value: { $0.systolic.map(Double.init) }),
             palette.warn),
            (Series(label: "SpO₂", unit: "%",    min: 85,  max: 100,
                    value: { $0.spo2.map(Double.init) }),
             palette.fg1),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas(rendersAsynchronously: false) { context, size in
                drawGrid(context: context, size: size)
                drawAxisLabels(context: context, size: size)
                drawSeries(context: context, size: size)
            }
            legend
                .padding(.leading, leftInset + 4)
                .padding(.top, 6)

            if history.samples.isEmpty {
                Text("No trend yet")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.fg2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .playgroundEditable(
            ElementID(screen: .vitals, category: .trendChart, slot: "primary"),
            hint: ElementHint(
                label: "Vitals trend chart",
                supports: [.visibility, .frame]
            )
        )
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(0..<seriesList.count, id: \.self) { idx in
                let entry = seriesList[idx]
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(entry.1)
                        .frame(width: 10, height: 2)
                    Text(entry.0.label)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.fg2)
                        .textCase(.uppercase)
                }
            }
        }
    }

    // MARK: - Plot area helpers

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: leftInset,
            y: topInset,
            width: max(0, size.width - leftInset - rightInset),
            height: max(0, size.height - topInset - bottomInset)
        )
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let rect = plotRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }

        var grid = Path()
        let lines = 4
        for i in 0...lines {
            let y = rect.minY + (rect.height / CGFloat(lines)) * CGFloat(i)
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(palette.line.opacity(0.5)),
            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
        )

        // Plot frame baseline (subtle)
        var frame = Path()
        frame.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        frame.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.stroke(frame, with: .color(palette.line), lineWidth: 0.5)
    }

    // MARK: - Axis labels

    private func drawAxisLabels(context: GraphicsContext, size: CGSize) {
        let rect = plotRect(in: size)
        guard rect.width > 0 else { return }

        let leftText = Text("−15m")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.fg3)
        let rightText = Text("NOW")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.fg3)

        context.draw(
            leftText,
            at: CGPoint(x: rect.minX, y: rect.maxY + 10),
            anchor: .topLeading
        )
        context.draw(
            rightText,
            at: CGPoint(x: rect.maxX, y: rect.maxY + 10),
            anchor: .topTrailing
        )
    }

    // MARK: - Series rendering

    private func drawSeries(context: GraphicsContext, size: CGSize) {
        let rect = plotRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }

        let samples = history.sampledForDisplay(80)
        guard samples.count >= 1 else { return }

        // X-axis: based on actual time span.
        let now = Date()
        let span: TimeInterval = history.retention
        let earliest = now.addingTimeInterval(-span)

        func xFor(_ sample: VitalsHistorySample) -> CGFloat {
            let t = sample.timestamp.timeIntervalSince(earliest)
            let frac = max(0, min(1, t / span))
            return rect.minX + CGFloat(frac) * rect.width
        }

        for (series, color) in seriesList {
            // Gather (x, y) pairs only where the field is present.
            var points: [CGPoint] = []
            for s in samples {
                guard let raw = series.value(s) else { continue }
                let clamped = max(series.min, min(series.max, raw))
                let yFrac = (clamped - series.min) / (series.max - series.min)
                let y = rect.maxY - CGFloat(yFrac) * rect.height
                points.append(CGPoint(x: xFor(s), y: y))
            }

            guard !points.isEmpty else { continue }

            // Line
            if points.count >= 2 {
                var path = Path()
                path.move(to: points[0])
                for p in points.dropFirst() { path.addLine(to: p) }
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
            }

            // Trailing dot at the most recent sample
            if let last = points.last {
                let dot = Path(ellipseIn: CGRect(
                    x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5
                ))
                context.fill(dot, with: .color(color))
            }
        }
    }
}
