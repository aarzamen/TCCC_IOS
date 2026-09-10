import SwiftUI

/// One observation. Nil or nonfinite values are unknown and break the plotted line.
public struct VitalSample: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let value: Double?
    public init(id: String, timestamp: Date, value: Double?) {
        self.id = id; self.timestamp = timestamp; self.value = value
    }
}

/// A caller-defined reference interval; it does not classify observations.
public struct VitalReferenceBand: Equatable, Sendable {
    public let lower: Double
    public let upper: Double
    public let label: String
    public init(lower: Double, upper: Double, label: String) {
        self.lower = lower; self.upper = upper; self.label = label
    }
    var validRange: ClosedRange<Double>? {
        lower.isFinite && upper.isFinite && lower <= upper ? lower...upper : nil
    }
}

enum DataDisplay {
    static func value(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unknown" }
        return value.formatted(.number.precision(.significantDigits(1...15)))
    }
    static func date(_ date: Date, timeZone: TimeZone) -> String {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, (-62_135_596_800...253_402_300_799).contains(seconds) else { return "Unknown time" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.string(from: date)
    }
}

struct TrendPoint: Equatable {
    let x: Double
    let y: Double
}

/// Uses scaled subtraction so finite extremes cannot overflow the chart domain.
struct TrendPlot {
    let segments: [[TrendPoint]]
    let bandRange: ClosedRange<Double>?
    let ordered: [VitalSample]

    init(samples: [VitalSample], band: VitalReferenceBand?) {
        ordered = samples.enumerated().filter { $0.element.timestamp.timeIntervalSince1970.isFinite }
            .sorted {
                let a = $0.element.timestamp, b = $1.element.timestamp
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
        let values = ordered.compactMap { sample -> Double? in
            guard let value = sample.value, value.isFinite else { return nil }
            return value
        }
        let reference = band?.validRange
        let domain = values + (reference.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let minimum = domain.min() ?? 0, maximum = domain.max() ?? 0
        let first = ordered.first?.timestamp.timeIntervalSince1970 ?? 0
        let last = ordered.last?.timestamp.timeIntervalSince1970 ?? 0
        var result: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        for sample in ordered {
            guard let value = sample.value, value.isFinite else {
                if !current.isEmpty { result.append(current); current = [] }
                continue
            }
            current.append(TrendPoint(x: Self.fraction(sample.timestamp.timeIntervalSince1970, lower: first, upper: last),
                                      y: 1 - Self.fraction(value, lower: minimum, upper: maximum)))
        }
        if !current.isEmpty { result.append(current) }
        segments = result
        bandRange = reference.map {
            let top = 1 - Self.fraction($0.upperBound, lower: minimum, upper: maximum)
            let bottom = 1 - Self.fraction($0.lowerBound, lower: minimum, upper: maximum)
            return top...bottom
        }
    }

    private static func fraction(_ value: Double, lower: Double, upper: Double) -> Double {
        guard lower != upper else { return 0.5 }
        let scale = max(abs(lower), abs(upper), abs(value))
        guard scale > 0, scale.isFinite else { return 0.5 }
        let denominator = upper / scale - lower / scale
        guard denominator > 0 else { return 0.5 }
        return min(1, max(0, (value / scale - lower / scale) / denominator))
    }

    func latestValue(from samples: [VitalSample]) -> Double? {
        // Ties have the same contract as the plot: the last supplied observation wins.
        let latest = samples.enumerated().filter { $0.element.timestamp.timeIntervalSince1970.isFinite }.max {
            let a = $0.element.timestamp, b = $1.element.timestamp
            return a == b ? $0.offset < $1.offset : a < b
        }
        guard let value = latest?.element.value, value.isFinite else { return nil }
        return value
    }
}

/// Native, time-spaced plot. Status and color are supplied by the caller, never inferred.
public struct VitalTrend: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    @State private var showsData = false
    private let label: String
    private let unit: String
    private let samples: [VitalSample]
    private let referenceBand: VitalReferenceBand?
    private let status: String?
    private let tone: SemanticRole
    private let timeZone: TimeZone

    public init(label: String, unit: String, samples: [VitalSample], referenceBand: VitalReferenceBand? = nil,
                status: String? = nil, tone: SemanticRole = .ink, timeZone: TimeZone = .gmt) {
        self.label = label; self.unit = unit; self.samples = samples; self.referenceBand = referenceBand
        self.status = status; self.tone = tone; self.timeZone = timeZone
    }

    public var body: some View {
        let plot = TrendPlot(samples: samples, band: referenceBand)
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.headline).accessibilityAddTraits(.isHeader)
            Text("\(DataDisplay.value(plot.latestValue(from: samples))) \(unit)")
                .font(.title2.monospaced().weight(.bold)).foregroundStyle(theme.color(tone))
                .fixedSize(horizontal: false, vertical: true)
            if let status { Text(status).font(.subheadline).foregroundStyle(theme.color(tone)) }
            if plot.segments.isEmpty {
                Text("No recorded values to plot").foregroundStyle(theme.color(.muted)).frame(minHeight: metrics.row)
            } else {
                Canvas { context, size in
                    let inset: CGFloat = 5
                    let width = max(0, size.width - inset * 2), height = max(0, size.height - inset * 2)
                    if let band = plot.bandRange {
                        let rect = CGRect(x: inset, y: inset + band.lowerBound * height, width: width,
                                          height: max(1, (band.upperBound - band.lowerBound) * height))
                        context.fill(Path(rect), with: .color(theme.color(.muted).opacity(0.16)))
                    }
                    for segment in plot.segments {
                        var path = Path()
                        for (index, point) in segment.enumerated() {
                            let position = CGPoint(x: inset + point.x * width, y: inset + point.y * height)
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            context.fill(Path(ellipseIn: CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)), with: .color(theme.color(tone)))
                        }
                        context.stroke(path, with: .color(theme.color(tone)), lineWidth: 2)
                    }
                }
                .frame(height: 84 * metrics.scale).accessibilityHidden(true)
                if let first = plot.ordered.first, let last = plot.ordered.last {
                    Text("\(DataDisplay.date(first.timestamp, timeZone: timeZone)) → \(DataDisplay.date(last.timestamp, timeZone: timeZone))")
                        .font(.caption.monospaced()).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let band = referenceBand {
                Text(band.validRange == nil ? "Reference band unavailable" : "\(band.label): \(DataDisplay.value(band.lower))–\(DataDisplay.value(band.upper)) \(unit)")
                    .font(.caption).foregroundStyle(theme.color(.muted))
            }
            ActionButton(showsData ? "Hide recorded data" : "Show recorded data", variant: .ghost,
                         systemImage: showsData ? "chevron.up" : "chevron.down") { showsData.toggle() }
            if showsData {
                if samples.isEmpty { Text("No observations supplied").foregroundStyle(theme.color(.muted)) }
                // Offsets intentionally retain every observation, including duplicate caller IDs.
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DataDisplay.date(sample.timestamp, timeZone: timeZone)).font(.caption.monospaced())
                        Text("\(DataDisplay.value(sample.value)) \(unit)").font(.body.monospaced())
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .foregroundStyle(theme.color(.ink)).padding(14)
        .background(theme.palette.panel2.color, in: RoundedRectangle(cornerRadius: 6))
    }
}

#if DEBUG
#Preview("VitalTrend · matrix") {
    PreviewMatrix("VitalTrend") { scenario in
        VitalTrend(label: "Synthetic pulse", unit: "beats/min", samples: scenario.isEmpty ? [] : [
            VitalSample(id: "1", timestamp: Date(timeIntervalSince1970: 600), value: 91),
            VitalSample(id: "2", timestamp: Date(timeIntervalSince1970: 660), value: 94),
            VitalSample(id: "3", timestamp: Date(timeIntervalSince1970: 780), value: nil),
            VitalSample(id: "4", timestamp: Date(timeIntervalSince1970: 900), value: 97)
        ], referenceBand: scenario.isEmpty ? nil : VitalReferenceBand(lower: 80, upper: 100, label: "Synthetic caller band"),
                   status: scenario.isEmpty ? nil : "Synthetic status supplied by caller", tone: .accent)
    }
}
#endif
