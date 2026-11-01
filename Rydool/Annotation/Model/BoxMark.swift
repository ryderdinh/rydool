import AppKit

/// An outline defined by opposite corners, regardless of drag direction.
struct BoxMark: DrawableMark {
    let start: CGPoint
    var end: CGPoint
    let style: MarkAppearance

    var rect: CGRect {
        CGRect(x: start.x, y: start.y,
               width: end.x - start.x, height: end.y - start.y).standardized
    }

    var isEmpty: Bool { max(rect.width, rect.height) < 3 }

    func draw(in context: CGContext) {
        let bounds = rect
        let rounding = min(style.lineWidth, min(bounds.width, bounds.height) / 2)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        context.setLineJoin(.round)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: rounding,
                               cornerHeight: rounding, transform: nil))
        context.strokePath()
    }
}
