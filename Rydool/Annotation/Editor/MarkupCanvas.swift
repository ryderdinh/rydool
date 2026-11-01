import AppKit

/// Displays committed marks and a single active drawing gesture.
final class MarkupCanvas: NSView {
    private enum Gesture {
        case freehand(FreehandMark)
        case arrow(ArrowMark)
        case box(BoxMark)

        mutating func move(to point: CGPoint) {
            switch self {
            case .freehand(var mark):
                mark.add(point)
                self = .freehand(mark)
            case .arrow(var mark):
                mark.end = point
                self = .arrow(mark)
            case .box(var mark):
                mark.end = point
                self = .box(mark)
            }
        }

        var annotation: DrawableMark {
            switch self {
            case .freehand(let mark): mark
            case .arrow(let mark): mark
            case .box(let mark): mark
            }
        }
    }

    private(set) var annotations: [DrawableMark] = []
    private var gesture: Gesture?
    var clipRect: CGRect? { didSet { needsDisplay = true } }
    var hasAnnotations: Bool { !annotations.isEmpty }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func begin(_ tool: AnnotationTool, at point: CGPoint, style: MarkAppearance) {
        switch tool {
        case .pen:
            gesture = .freehand(FreehandMark(start: point, style: style))
        case .arrow:
            gesture = .arrow(ArrowMark(start: point, end: point, style: style))
        case .rectangle:
            gesture = .box(BoxMark(start: point, end: point, style: style))
        case .text:
            gesture = nil
        }
        needsDisplay = true
    }

    func update(to point: CGPoint) {
        guard gesture != nil else { return }
        gesture?.move(to: point)
        needsDisplay = true
    }

    func end() {
        if let mark = gesture?.annotation { add(mark) }
        gesture = nil
        needsDisplay = true
    }

    func add(_ annotation: DrawableMark) {
        if !annotation.isEmpty {
            annotations.append(annotation)
            needsDisplay = true
        }
    }

    @discardableResult
    func undo() -> Bool {
        guard annotations.popLast() != nil else { return false }
        needsDisplay = true
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection = clipRect, let graphics = NSGraphicsContext.current?.cgContext else { return }
        graphics.saveGState()
        defer { graphics.restoreGState() }
        graphics.clip(to: selection)
        annotations.forEach { $0.draw(in: graphics) }
        gesture?.annotation.draw(in: graphics)
    }
}
