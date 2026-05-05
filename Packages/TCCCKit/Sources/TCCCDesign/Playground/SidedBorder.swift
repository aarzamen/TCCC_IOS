import SwiftUI

/// A rectangular border that lets each edge be hidden independently.
/// Falls back to identical behaviour as
/// `Rectangle().strokeBorder(width: w)` when `hidden` is empty.
///
/// Used by `Panel` (and any other surface with a stroked frame) to
/// support the playground's per-edge border deletion. Visually
/// identical to a plain rectangle when no overrides are active.
public struct SidedBorder: Shape {
    public var hidden: BorderEdges
    public var lineWidth: CGFloat

    public init(hidden: BorderEdges = .none, lineWidth: CGFloat = 1) {
        self.hidden = hidden
        self.lineWidth = lineWidth
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()

        // Insets so the stroke sits inside the rect, matching
        // `.strokeBorder` semantics.
        let half = lineWidth / 2

        if !hidden.contains(.top) {
            p.move(to:    CGPoint(x: rect.minX, y: rect.minY + half))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + half))
        }
        if !hidden.contains(.bottom) {
            p.move(to:    CGPoint(x: rect.minX, y: rect.maxY - half))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - half))
        }
        if !hidden.contains(.leading) {
            p.move(to:    CGPoint(x: rect.minX + half, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + half, y: rect.maxY))
        }
        if !hidden.contains(.trailing) {
            p.move(to:    CGPoint(x: rect.maxX - half, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - half, y: rect.maxY))
        }

        return p.strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}
