import AppKit

/// Records pointer samples in image coordinates for a freehand stroke.
struct FreehandMark: DrawableMark {
    private(set) var points: [CGPoint]
    let style: MarkAppearance

    init(start: CGPoint, style: MarkAppearance) {
        self.style = style
        self.points = [start]
    }

    var isEmpty: Bool { points.count == 0 }

    mutating func add(_ point: CGPoint) {
        if let previous = points.last {
            let x = point.x - previous.x
            let y = point.y - previous.y
            if x * x + y * y < 0.75 * 0.75 { return }
        }
        points.append(point)
    }

    func draw(in context: CGContext) {
        guard let origin = points.first else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        guard points.count > 1 else {
            let radius = style.lineWidth / 2
            context.fillEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius,
                                           width: radius * 2, height: radius * 2))
            return
        }

        // Interpolate through the samples with cubic segments for smooth ink.
        let path = CGMutablePath()
        path.move(to: origin)
        for index in 0..<(points.count - 1) {
            let a = points[max(index - 1, 0)]
            let b = points[index]
            let c = points[index + 1]
            let d = points[min(index + 2, points.count - 1)]
            let firstControl = CGPoint(x: b.x + (c.x - a.x) / 6,
                                       y: b.y + (c.y - a.y) / 6)
            let secondControl = CGPoint(x: c.x - (d.x - b.x) / 6,
                                        y: c.y - (d.y - b.y) / 6)
            path.addCurve(to: c, control1: firstControl, control2: secondControl)
        }
        context.addPath(path)
        context.strokePath()
    }
}
