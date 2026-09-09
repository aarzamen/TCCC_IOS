import SwiftUI
import TCCCDomain

/// DD 1380 Section B: regions from the recorded bleeding location, never
/// inferred wound coordinates, injury counts, or tourniquet placement.
struct BodyMap: View {
    let patient: PatientState?
    @Environment(\.palette) private var palette
    private var presentation: BodyMapPresentation { .init(patient: patient) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Patient’s right / left")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.fg1)
            HStack(spacing: 12) {
                silhouette(isPosterior: false)
                silhouette(isPosterior: true)
            }
            .frame(height: 136)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.location ?? "Bleeding location not recorded")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.fg)
                Text(presentation.regions.isEmpty ? presentation.placementNote : "Shaded region · \(presentation.placementNote.lowercased())")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.fg1)
                if let intervention = presentation.intervention {
                    Text("Recorded: \(intervention)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.fg1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bleeding location diagram. Patient right and left labeled on front and back views.")
        .accessibilityValue([
            presentation.location ?? "Bleeding location not recorded",
            presentation.placementNote,
            presentation.intervention.map { "Recorded: \($0)" }
        ].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier("card.bodyMap")
    }

    private func silhouette(isPosterior: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(isPosterior ? "L" : "R")
                Spacer(minLength: 0)
                Text(isPosterior ? "Back" : "Front")
                Spacer(minLength: 0)
                Text(isPosterior ? "R" : "L")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(palette.fg1)

            Canvas { context, size in
                let scale = min(size.width / 120, size.height / 200)
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(.init(translationX: (size.width - 120 * scale) / 2,
                                         y: (size.height - 200 * scale) / 2))
                let outline = Self.outline.applying(transform)
                context.fill(outline, with: .color(palette.bg3))
                context.stroke(outline, with: .color(palette.fg2),
                               style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))

                // Unknown surface: show the same REGION on both views, dashed,
                // with the uncertainty spelled out below. This is not two wounds.
                let visible = presentation.surface == .unspecified ||
                    (isPosterior ? presentation.surface == .back : presentation.surface == .front)
                if visible {
                    var shading = context
                    shading.clip(to: outline)
                    for region in presentation.regions {
                        let x = isPosterior ? 120 - region.centerX : region.centerX
                        let rect = CGRect(x: x - region.width / 2, y: region.centerY - region.height / 2,
                                          width: region.width, height: region.height)
                        let path = Path(roundedRect: rect, cornerRadius: 4).applying(transform)
                        shading.fill(path, with: .color(palette.crit.opacity(0.32)))
                        shading.stroke(path, with: .color(palette.crit),
                                       style: StrokeStyle(lineWidth: 1.7,
                                                          dash: presentation.surface == .unspecified ? [3, 2] : []))
                    }
                }
                context.stroke(Self.landmarks(isPosterior: isPosterior).applying(transform),
                               with: .color(palette.fg2.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Symmetric vector contour with separated arms, hands, knees and feet.
    /// Rounded vertices remain legible at landscape card size.
    private static var outline: Path {
        let half: [(CGFloat, CGFloat)] = [
            (55, 27), (54, 33), (39, 37), (34, 43), (25, 73),
            (18, 98), (14, 106), (15, 114), (21, 116), (27, 105),
            (27, 98), (36, 78), (42, 57), (45, 78), (45, 87),
            (41, 100), (41, 118), (43, 144), (44, 179),
            (38, 190), (38, 195), (52, 195), (56, 190), (55, 183),
            (56, 150), (60, 115)
        ]
        let points = (half + half.dropLast().reversed().map { (120 - $0.0, $0.1) })
            .map { CGPoint(x: $0.0, y: $0.1) }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var p = Path(ellipseIn: CGRect(x: 50, y: 3, width: 20, height: 25))
        p.move(to: midpoint(points.last!, points[0]))
        for i in points.indices {
            p.addQuadCurve(to: midpoint(points[i], points[(i + 1) % points.count]), control: points[i])
        }
        p.closeSubpath()
        return p
    }

    private static func landmarks(isPosterior: Bool) -> Path {
        var p = Path()
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
        }
        if isPosterior {
            line([(60, 36), (60, 99)])
            line([(47, 47), (52, 60), (57, 48)])
            line([(73, 47), (68, 60), (63, 48)])
            line([(46, 103), (53, 106), (60, 103), (67, 106), (74, 103)])
        } else {
            line([(46, 44), (54, 42), (60, 46), (66, 42), (74, 44)])
            line([(46, 60), (53, 63), (58, 61)])
            line([(74, 60), (67, 63), (62, 61)])
            p.addEllipse(in: CGRect(x: 59, y: 83, width: 2, height: 2))
            line([(46, 100), (60, 111), (74, 100)])
        }
        line([(45, 146), (49, 148), (54, 146)])
        line([(66, 146), (71, 148), (75, 146)])
        return p
    }
}
