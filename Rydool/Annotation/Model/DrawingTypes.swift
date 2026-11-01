import AppKit

/// A mark in overlay coordinates that can be rendered into any graphics context.
protocol DrawableMark {
    var isEmpty: Bool { get }
    func draw(in context: CGContext)
}

struct MarkAppearance {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen, arrow, rectangle, text
    var id: String { rawValue }

    private var metadata: (name: String, symbol: String, key: String) {
        switch self {
        case .pen: ("Pen", "pencil.tip", "p")
        case .arrow: ("Arrow", "arrow.up.right", "a")
        case .rectangle: ("Rectangle", "rectangle", "r")
        case .text: ("Text", "textformat", "t")
        }
    }
    var title: String { L(metadata.name) }
    var symbol: String { metadata.symbol }
    var key: String { metadata.key }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red, yellow, green, blue, black, white
    var id: String { rawValue }

    var nsColor: NSColor {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .red: rgb = (1.00, 0.23, 0.19)
        case .yellow: rgb = (1.00, 0.80, 0.00)
        case .green: rgb = (0.20, 0.78, 0.35)
        case .blue: rgb = (0.04, 0.52, 1.00)
        case .black: rgb = (0.10, 0.10, 0.10)
        case .white: rgb = (1.00, 1.00, 1.00)
        }
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
}

enum LineWeight: Int, CaseIterable {
    case thin, medium, thick
    private var metrics: (line: CGFloat, text: CGFloat, name: String) {
        switch self {
        case .thin: (2, 16, "Thin")
        case .medium: (4, 22, "Medium")
        case .thick: (7, 30, "Thick")
        }
    }
    var lineWidth: CGFloat { metrics.line }
    var fontSize: CGFloat { metrics.text }
    var title: String { L(metrics.name) }
    var next: LineWeight { LineWeight(rawValue: (rawValue + 1) % Self.allCases.count) ?? .thin }
}
