import AppKit

/// An arrow specified by its tail, tip, and visual style.
struct ArrowMark: DrawableMark {
    let start: CGPoint
    var end: CGPoint
    let style: MarkAppearance

    var isEmpty: Bool { start.distance(to: end) < 4 }

    func draw(in context: CGContext) {
        let length = start.distance(to: end)
        guard length > 1 else { return }
        let head = min(length, max(12, style.lineWidth * 3.5 + 6))

        // Construct the arrow horizontally, then rotate the drawing coordinate
        // system so the same geometry works in every direction.
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: start.x, y: start.y)
        context.rotate(by: atan2(end.y - start.y, end.x - start.x))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(style.lineWidth)
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)

        if length > head {
            context.strokeLineSegments(between: [.zero, CGPoint(x: length - head * 0.6, y: 0)])
        }
        let headPath = CGMutablePath()
        headPath.move(to: CGPoint(x: length, y: 0))
        headPath.addLine(to: CGPoint(x: length - head, y: -head * 0.55))
        headPath.addLine(to: CGPoint(x: length - head, y: head * 0.55))
        headPath.closeSubpath()
        context.addPath(headPath)
        context.fillPath()
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}
