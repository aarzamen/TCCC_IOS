import SwiftUI

struct MapPlotView: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            let palette = palette
            let width = size.width
            let height = size.height

            // Graticule (20pt grid)
            var grid = Path()
            let step: CGFloat = 20
            var x: CGFloat = 0
            while x <= width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: height))
                x += step
            }
            var y: CGFloat = 0
            while y <= height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: width, y: y))
                y += step
            }
            context.stroke(grid, with: .color(palette.grid), lineWidth: 0.5)

            // Three contour curves
            let contourStroke = StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
            for offset in stride(from: -40, through: 40, by: 30) {
                var contour = Path()
                let baseY = height * 0.5 + CGFloat(offset)
                contour.move(to: CGPoint(x: 0, y: baseY))
                let segments = 5
                for i in 1...segments {
                    let cx = (width / CGFloat(segments)) * CGFloat(i - 1) + width / CGFloat(segments * 2)
                    let cy = baseY + CGFloat.random(in: -8...8)
                    let ex = (width / CGFloat(segments)) * CGFloat(i)
                    let ey = baseY + CGFloat.random(in: -10...10)
                    contour.addQuadCurve(to: CGPoint(x: ex, y: ey), control: CGPoint(x: cx, y: cy))
                }
                context.stroke(contour, with: .color(palette.lineStrong.opacity(0.6)), style: contourStroke)
            }

            // Layout positions (relative to the canvas)
            let ccp = CGPoint(x: width * 0.4, y: height * 0.55)
            let lz = CGPoint(x: width * 0.72, y: height * 0.28)
            let threat = CGPoint(x: width * 0.22, y: height * 0.78)

            // Path from CCP → LZ (dashed)
            var path = Path()
            path.move(to: ccp)
            path.addLine(to: lz)
            context.stroke(
                path,
                with: .color(palette.accent),
                style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])
            )

            // CCP marker — dashed circle r=14, solid dot r=4
            let ccpRing = CGRect(x: ccp.x - 14, y: ccp.y - 14, width: 28, height: 28)
            context.stroke(
                Path(ellipseIn: ccpRing),
                with: .color(palette.accent),
                style: StrokeStyle(lineWidth: 1.0, dash: [3, 3])
            )
            let ccpDot = CGRect(x: ccp.x - 4, y: ccp.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: ccpDot), with: .color(palette.accent))

            // CCP label
            let ccpText = Text("CCP")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.accent)
            context.draw(ccpText, at: CGPoint(x: ccp.x - 16, y: ccp.y + 16))

            // LZ ALPHA — hollow square 20x20 with directional ticks
            let lzRect = CGRect(x: lz.x - 10, y: lz.y - 10, width: 20, height: 20)
            context.stroke(
                Path(lzRect),
                with: .color(palette.accentHot),
                style: StrokeStyle(lineWidth: 1.2)
            )
            // Directional ticks
            var ticks = Path()
            ticks.move(to: CGPoint(x: lz.x - 14, y: lz.y))
            ticks.addLine(to: CGPoint(x: lz.x - 10, y: lz.y))
            ticks.move(to: CGPoint(x: lz.x + 10, y: lz.y))
            ticks.addLine(to: CGPoint(x: lz.x + 14, y: lz.y))
            ticks.move(to: CGPoint(x: lz.x, y: lz.y - 14))
            ticks.addLine(to: CGPoint(x: lz.x, y: lz.y - 10))
            ticks.move(to: CGPoint(x: lz.x, y: lz.y + 10))
            ticks.addLine(to: CGPoint(x: lz.x, y: lz.y + 14))
            context.stroke(ticks, with: .color(palette.accentHot), lineWidth: 1.2)
            let lzText = Text("LZ ALPHA")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.accentHot)
            context.draw(lzText, at: CGPoint(x: lz.x + 14, y: lz.y - 12))

            // Threat marker — hollow triangle in warn color
            var triangle = Path()
            triangle.move(to: CGPoint(x: threat.x, y: threat.y - 7))
            triangle.addLine(to: CGPoint(x: threat.x + 7, y: threat.y + 5))
            triangle.addLine(to: CGPoint(x: threat.x - 7, y: threat.y + 5))
            triangle.closeSubpath()
            context.stroke(triangle, with: .color(palette.warn), lineWidth: 1.2)
            let suspText = Text("SUSP")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.warn)
            context.draw(suspText, at: CGPoint(x: threat.x, y: threat.y + 14))

            // Scale bar — bottom-left corner, 40pt = 500m
            let scaleY = height - 12
            var scale = Path()
            scale.move(to: CGPoint(x: 14, y: scaleY))
            scale.addLine(to: CGPoint(x: 54, y: scaleY))
            scale.move(to: CGPoint(x: 14, y: scaleY - 3))
            scale.addLine(to: CGPoint(x: 14, y: scaleY + 3))
            scale.move(to: CGPoint(x: 54, y: scaleY - 3))
            scale.addLine(to: CGPoint(x: 54, y: scaleY + 3))
            context.stroke(scale, with: .color(palette.fg3), lineWidth: 0.8)
            let scaleText = Text("500 m")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg3)
            context.draw(scaleText, at: CGPoint(x: 70, y: scaleY))
        }
        .overlay(alignment: .topLeading) {
            Text("42S WD")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .padding(.top, 6)
                .padding(.leading, 6)
        }
        .overlay(alignment: .topTrailing) {
            Text("N ↑")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.fg3)
                .padding(.top, 6)
                .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
