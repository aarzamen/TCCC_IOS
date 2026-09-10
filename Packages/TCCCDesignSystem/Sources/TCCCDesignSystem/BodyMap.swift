import SwiftUI

public enum BodySide: String, CaseIterable, Sendable {
    case anterior, posterior
    public var title: String { self == .anterior ? "Front · anterior" : "Back · posterior" }
}

public enum BodyRegion: String, CaseIterable, Sendable {
    case head, chest, abdomen, rightArm, leftArm, rightLeg, leftLeg
    public var title: String {
        switch self {
        case .head: "Head"
        case .chest: "Chest"
        case .abdomen: "Abdomen"
        case .rightArm: "Right arm"
        case .leftArm: "Left arm"
        case .rightLeg: "Right leg"
        case .leftLeg: "Left leg"
        }
    }
}

public struct BodyMark: Hashable, Sendable {
    public let side: BodySide
    public let region: BodyRegion
    public init(side: BodySide, region: BodyRegion) { self.side = side; self.region = region }
}

/// Rectangles are the actual button targets. Four columns keep two full-width legs
/// between two full-width arms, with positive gaps and no enlarged overlapping hits.
struct BodyGeometry {
    let tap: CGFloat
    let gap: CGFloat
    init(tap: CGFloat) { self.tap = max(44, tap.isFinite ? tap : 44); gap = 6 }
    var size: CGSize { CGSize(width: 4 * tap + 3 * gap, height: 5 * tap + 3 * gap) }
    func rect(for region: BodyRegion, side: BodySide) -> CGRect {
        let centerX = tap + gap
        let torsoWidth = 2 * tap + gap
        let rightOnLeft = side == .anterior
        switch region {
        case .head:
            return CGRect(x: (size.width - tap) / 2, y: 0, width: tap, height: tap)
        case .chest:
            return CGRect(x: centerX, y: tap + gap, width: torsoWidth, height: tap)
        case .abdomen:
            return CGRect(x: centerX, y: 2 * (tap + gap), width: torsoWidth, height: tap)
        case .rightArm, .leftArm:
            let onLeft = (region == .rightArm) == rightOnLeft
            return CGRect(x: onLeft ? 0 : 3 * (tap + gap), y: tap + gap, width: tap, height: 2 * tap + gap)
        case .rightLeg, .leftLeg:
            let onLeft = (region == .rightLeg) == rightOnLeft
            return CGRect(x: onLeft ? centerX : 2 * (tap + gap), y: 3 * (tap + gap), width: tap, height: 2 * tap)
        }
    }
}

private struct BodyRegionShape: Shape {
    let region: BodyRegion
    func path(in rect: CGRect) -> Path {
        if region == .head { return Path(ellipseIn: rect.insetBy(dx: rect.width * 0.07, dy: 0)) }
        var path = Path()
        let inset: CGFloat = region == .chest ? 0 : rect.width * 0.08
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Caller owns the marks. This diagram records no injury classification or clinical state.
public struct BodyMap: View {
    @Environment(\.tcccTheme) private var theme
    @DesignMetrics private var metrics
    private let marks: Set<BodyMark>
    private let onToggle: ((BodyMark) -> Void)?

    public init(marks: Set<BodyMark>, onToggle: ((BodyMark) -> Void)? = nil) {
        self.marks = marks; self.onToggle = onToggle
    }

    public var body: some View {
        let geometry = BodyGeometry(tap: metrics.tap)
        VStack(alignment: .leading, spacing: 12) {
            Text("Body regions").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Patient’s right and left are labeled on each figure.").font(.caption).foregroundStyle(theme.color(.muted))
            // Figures keep their native target size; narrow/large-text layouts scroll.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(BodySide.allCases, id: \.self) { side in figure(side, geometry: geometry) }
                }.padding(4)
            }
            if marks.isEmpty {
                Text("No regions marked").foregroundStyle(theme.color(.muted))
            } else {
                Text("Marked regions").font(.subheadline.weight(.semibold))
                ForEach(BodySide.allCases, id: \.self) { side in
                    ForEach(BodyRegion.allCases.filter { marks.contains(BodyMark(side: side, region: $0)) }, id: \.self) { region in
                        Label("\(region.title) · \(side.title)", systemImage: "xmark")
                            .font(.body.monospaced()).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(onToggle == nil ? "Read only — region editing unavailable" : "Tap a region to toggle its mark. X indicates a marked region.")
                .font(.caption).foregroundStyle(theme.color(.muted))
        }
        .padding(14).foregroundStyle(theme.color(.ink))
    }

    private func figure(_ side: BodySide, geometry: BodyGeometry) -> some View {
        VStack(spacing: 10) {
            Text(side.title).font(.headline).accessibilityAddTraits(.isHeader)
            HStack {
                Text(side == .anterior ? "Patient R" : "Patient L")
                Spacer()
                Text(side == .anterior ? "Patient L" : "Patient R")
            }.font(.caption.monospaced()).foregroundStyle(theme.color(.muted))
            ZStack(alignment: .topLeading) {
                ForEach(BodyRegion.allCases, id: \.self) { region in
                    let rect = geometry.rect(for: region, side: side)
                    regionButton(BodyMark(side: side, region: region))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.frame(width: geometry.size.width)
    }

    private func regionButton(_ mark: BodyMark) -> some View {
        let selected = marks.contains(mark)
        return Button { onToggle?(mark) } label: {
            ZStack {
                BodyRegionShape(region: mark.region)
                    .fill(selected ? theme.color(.danger).opacity(0.28) : theme.palette.panel2.color)
                BodyRegionShape(region: mark.region)
                    .stroke(selected ? theme.color(.danger) : theme.palette.line.color, lineWidth: selected ? 2 : 1.5)
                if selected { Image(systemName: "xmark").font(.title3.weight(.bold)).foregroundStyle(theme.color(.danger)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(onToggle == nil)
        .accessibilityLabel("\(mark.region.title), \(mark.side.title)")
        .accessibilityValue(selected ? "Marked, X" : "Not marked")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(onToggle == nil ? "Region editing unavailable" : "Toggle region mark")
    }
}

#if DEBUG
private struct BodyMapExample: View {
    @State private var marks: Set<BodyMark>
    init(empty: Bool) {
        _marks = State(initialValue: empty ? [] : [BodyMark(side: .anterior, region: .rightArm), BodyMark(side: .posterior, region: .rightLeg)])
    }
    var body: some View {
        BodyMap(marks: marks) { mark in
            if marks.contains(mark) { marks.remove(mark) } else { marks.insert(mark) }
        }
    }
}
#Preview("BodyMap · matrix") {
    PreviewMatrix("BodyMap") { BodyMapExample(empty: $0.isEmpty) }
}
#endif
