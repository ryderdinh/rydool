import AppKit

/// The eight resize directions in a top-left-origin coordinate space.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    private var axes: (horizontal: Int, vertical: Int) {
        switch self {
        case .topLeft: (-1, -1)
        case .top: (0, -1)
        case .topRight: (1, -1)
        case .right: (1, 0)
        case .bottomRight: (1, 1)
        case .bottom: (0, 1)
        case .bottomLeft: (-1, 1)
        case .left: (-1, 0)
        }
    }

    var isCorner: Bool { axes.horizontal != 0 && axes.vertical != 0 }

    func point(in rect: CGRect) -> CGPoint {
        let axes = axes
        return CGPoint(x: rect.midX + CGFloat(axes.horizontal) * rect.width / 2,
                       y: rect.midY + CGFloat(axes.vertical) * rect.height / 2)
    }

    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return .frameResize(position: position, directions: .all)
        }
        if axes.horizontal == 0 { return .resizeUpDown }
        if axes.vertical == 0 { return .resizeLeftRight }
        return .crosshair
    }

    fileprivate var horizontal: Int { axes.horizontal }
    fileprivate var vertical: Int { axes.vertical }
}

/// Keeps the user's selection inside one display, expressed in overlay points.
struct SelectionManager {
    let bounds: CGRect
    private(set) var rect: CGRect?
    static let minimumSize: CGFloat = 4

    init(bounds: CGRect) { self.bounds = bounds }

    mutating func set(_ newRect: CGRect?) {
        rect = newRect.map { constrain($0) }
    }

    mutating func clear() { rect = nil }

    func rect(from anchor: CGPoint, to point: CGPoint) -> CGRect {
        let proposed = CGRect(x: anchor.x, y: anchor.y,
                              width: point.x - anchor.x, height: point.y - anchor.y)
        return constrain(proposed)
    }

    func handle(at point: CGPoint) -> SelectionHandle? {
        guard let rect else { return nil }
        // Corners win when a small selection makes multiple handles overlap.
        let candidates = SelectionHandle.allCases.sorted { $0.isCorner && !$1.isCorner }
        for handle in candidates {
            let center = handle.point(in: rect)
            let dx = center.x - point.x
            let dy = center.y - point.y
            if dx * dx + dy * dy <= 81 { return handle }
        }
        let tolerance: CGFloat = 4
        if point.y >= rect.minY - tolerance && point.y <= rect.maxY + tolerance {
            if abs(point.x - rect.minX) <= tolerance { return .left }
            if abs(point.x - rect.maxX) <= tolerance { return .right }
        }
        if point.x >= rect.minX - tolerance && point.x <= rect.maxX + tolerance {
            if abs(point.y - rect.minY) <= tolerance { return .top }
            if abs(point.y - rect.maxY) <= tolerance { return .bottom }
        }
        return nil
    }

    func moved(_ start: CGRect, by delta: CGSize) -> CGRect {
        let x = min(max(bounds.minX, start.minX + delta.width), bounds.maxX - start.width)
        let y = min(max(bounds.minY, start.minY + delta.height), bounds.maxY - start.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: start.size)
    }

    func resized(_ start: CGRect, handle: SelectionHandle, by delta: CGSize) -> CGRect {
        let horizontal = handle.horizontal
        let vertical = handle.vertical
        let left = start.minX + (horizontal == -1 ? delta.width : 0)
        let right = start.maxX + (horizontal == 1 ? delta.width : 0)
        let top = start.minY + (vertical == -1 ? delta.height : 0)
        let bottom = start.maxY + (vertical == 1 ? delta.height : 0)
        return constrain(CGRect(x: left, y: top, width: right - left, height: bottom - top))
    }

    private func constrain(_ proposed: CGRect) -> CGRect {
        let clipped = proposed.standardized.intersection(bounds)
        guard !clipped.isNull else { return .zero }
        let x0 = clipped.minX.rounded()
        let y0 = clipped.minY.rounded()
        let x1 = clipped.maxX.rounded()
        let y1 = clipped.maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// Decorative overlay; events are handled by the underlying capture view.
final class SelectionChromeView: NSView {
    var selection: CGRect? { didSet { needsDisplay = true } }
    var showsHandles = false { didSet { needsDisplay = true } }
    var imagePixelSize: CGSize = .zero { didSet { needsDisplay = true } }
    var displayedPixelSize: CGSize? { didSet { needsDisplay = true } }
    var showsDimensions = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        guard let selected = selection, selected.width > 0, selected.height > 0 else {
            dirtyRect.fill()
            return
        }
        // Fill four rectangles around the selected area instead of clearing
        // the selection itself, so the captured desktop remains visible.
        let frame = bounds
        let shade = [
            CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(0, selected.minY - frame.minY)),
            CGRect(x: frame.minX, y: selected.maxY, width: frame.width, height: max(0, frame.maxY - selected.maxY)),
            CGRect(x: frame.minX, y: selected.minY, width: max(0, selected.minX - frame.minX), height: selected.height),
            CGRect(x: selected.maxX, y: selected.minY, width: max(0, frame.maxX - selected.maxX), height: selected.height)
        ]
        shade.forEach { $0.fill() }
        let outline = NSBezierPath(rect: selected)
        outline.lineWidth = 3
        NSColor.black.withAlphaComponent(0.55).setStroke()
        outline.stroke()
        outline.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        outline.stroke()
        if showsHandles { drawHandles(in: selected) }
        if showsDimensions { drawDimensions(in: selected) }
    }

    private func drawHandles(in rect: CGRect) {
        for handle in SelectionHandle.allCases {
            if !handle.isCorner && min(rect.width, rect.height) < 40 { continue }
            let p = handle.point(in: rect)
            let path = NSBezierPath(ovalIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 3
            path.stroke()
            NSColor.white.setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawDimensions(in rect: CGRect) {
        let sizeInPixels = displayedPixelSize ?? PixelMapping(imageSize: imagePixelSize, viewSize: bounds.size, selection: rect)?.crop.size
        guard let sizeInPixels else { return }
        let label = "\(Int(sizeInPixels.width)) × \(Int(sizeInPixels.height)) px" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = label.size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 22, height: ceil(textSize.height) + 10)
        var x = rect.minX
        var y = rect.minY - size.height - 6
        if y < bounds.minY + 4 { x += 6; y = rect.minY + 6 }
        x = min(max(bounds.minX + 4, x), bounds.maxX - size.width - 4)
        let badge = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let path = NSBezierPath(roundedRect: badge, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor(calibratedWhite: 0.08, alpha: 0.90).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: CGRect(x: x + 8, y: y + (size.height - 5) / 2, width: 5, height: 5)).fill()
        label.draw(at: CGPoint(x: x + 16, y: y + 5), withAttributes: attributes)
    }
}
