import SwiftUI
import TCCCDomain

struct BodyMap: View {
    let patient: PatientState?

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let palette = palette
            let scale = min(size.width / 120, size.height / 200)
            let dx = (size.width - 120 * scale) / 2
            let dy = (size.height - 200 * scale) / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: dx + x * scale, y: dy + y * scale)
            }

            let stroke = palette.lineStrong
            let strokeWidth: CGFloat = 1.2

            // Head
            let headRect = CGRect(
                x: point(50, 6).x,
                y: point(50, 6).y,
                width: 20 * scale,
                height: 22 * scale
            )
            context.stroke(Path(ellipseIn: headRect), with: .color(stroke), lineWidth: strokeWidth)

            // Neck
            var neck = Path()
            neck.move(to: point(56, 28))
            neck.addLine(to: point(56, 36))
            neck.move(to: point(64, 28))
            neck.addLine(to: point(64, 36))
            context.stroke(neck, with: .color(stroke), lineWidth: strokeWidth)

            // Torso
            var torso = Path()
            torso.move(to: point(50, 36))
            torso.addLine(to: point(70, 36))
            torso.addLine(to: point(78, 50))
            torso.addLine(to: point(76, 100))
            torso.addLine(to: point(60, 110))
            torso.addLine(to: point(44, 100))
            torso.addLine(to: point(42, 50))
            torso.closeSubpath()
            context.stroke(torso, with: .color(stroke), lineWidth: strokeWidth)

            // Arms
            var arms = Path()
            arms.move(to: point(42, 50))
            arms.addLine(to: point(28, 90))
            arms.addLine(to: point(30, 110))
            arms.move(to: point(78, 50))
            arms.addLine(to: point(92, 90))
            arms.addLine(to: point(90, 110))
            context.stroke(arms, with: .color(stroke), lineWidth: strokeWidth)

            // Legs
            var legs = Path()
            legs.move(to: point(50, 110))
            legs.addLine(to: point(46, 175))
            legs.addLine(to: point(48, 195))
            legs.move(to: point(70, 110))
            legs.addLine(to: point(74, 175))
            legs.addLine(to: point(72, 195))
            context.stroke(legs, with: .color(stroke), lineWidth: strokeWidth)

            // Markers based on patient state
            drawMarkers(context: &context, point: point, scale: scale)
        }
        .overlay(alignment: .topLeading) {
            Text("ANT")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.fg3)
                .padding(.top, 4)
                .padding(.leading, 4)
        }
        .overlay(alignment: .topTrailing) {
            Text("L ← → R")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.fg3)
                .padding(.top, 4)
                .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawMarkers(
        context: inout GraphicsContext,
        point: (CGFloat, CGFloat) -> CGPoint,
        scale: CGFloat
    ) {
        guard let patient else { return }
        let location = (patient.march.hemorrhageLocation ?? "").lowercased()
        let intervention = (patient.march.hemorrhageIntervention ?? "").lowercased()

        let marker = injuryPoint(forLocation: location, point: point)
        if let marker {
            // Halo
            let halo = CGRect(
                x: marker.x - 6 * scale,
                y: marker.y - 6 * scale,
                width: 12 * scale,
                height: 12 * scale
            )
            context.fill(Path(ellipseIn: halo), with: .color(palette.crit.opacity(0.25)))
            // Solid
            let dot = CGRect(
                x: marker.x - 3 * scale,
                y: marker.y - 3 * scale,
                width: 6 * scale,
                height: 6 * scale
            )
            context.fill(Path(ellipseIn: dot), with: .color(palette.crit))
        }

        // Tourniquet band (drawn slightly proximal to the injury)
        if intervention.contains("tourniquet") || intervention.contains("tq") || intervention.contains("cat") {
            let band = tourniquetRect(forLocation: location, point: point, scale: scale)
            if let band {
                context.fill(Path(band), with: .color(palette.accent))
            }
        }
    }

    private func injuryPoint(
        forLocation location: String,
        point: (CGFloat, CGFloat) -> CGPoint
    ) -> CGPoint? {
        // Right side from viewer perspective is the patient's left, but the design
        // brief shows wounds on patient's anatomical right (cx 74 in the brief).
        // We follow the brief's convention.
        if location.contains("right") && (location.contains("thigh") || location.contains("leg") || location.contains("femur")) {
            return point(74, 135)
        }
        if location.contains("left") && (location.contains("thigh") || location.contains("leg")) {
            return point(46, 135)
        }
        if location.contains("bilateral") && (location.contains("thigh") || location.contains("leg") || location.contains("extrem")) {
            return point(60, 135)
        }
        if location.contains("right") && location.contains("arm") {
            return point(86, 75)
        }
        if location.contains("left") && location.contains("arm") {
            return point(34, 75)
        }
        if location.contains("chest") || location.contains("abdom") {
            return point(60, 70)
        }
        return nil
    }

    private func tourniquetRect(
        forLocation location: String,
        point: (CGFloat, CGFloat) -> CGPoint,
        scale: CGFloat
    ) -> CGRect? {
        guard let injury = injuryPoint(forLocation: location, point: point) else { return nil }
        let bandWidth: CGFloat = 18 * scale
        let bandHeight: CGFloat = 3.5 * scale
        let bandY = injury.y - 22 * scale
        return CGRect(
            x: injury.x - bandWidth / 2,
            y: bandY,
            width: bandWidth,
            height: bandHeight
        )
    }
}
