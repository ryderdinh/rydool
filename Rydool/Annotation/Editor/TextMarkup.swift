import AppKit

/// Layout information is shared by the temporary editor and exported text.
private struct TextLayout {
    let style: MarkAppearance
    var font: NSFont { NSFont.systemFont(ofSize: style.fontSize, weight: .semibold) }
    var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: style.color] }

    func text(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: attributes)
    }

    func editorSize(for value: String, minimumWidth: CGFloat) -> CGSize {
        // Measure each line independently so a trailing newline remains editable.
        let lines = value.components(separatedBy: "\n")
        let maxWidth = lines.reduce(CGFloat.zero) { width, line in
            let measure = (line as NSString).size(withAttributes: attributes).width
            return max(width, measure)
        }
        let lineHeight = font.ascender - font.descender + font.leading
        return CGSize(width: max(minimumWidth, ceil(maxWidth) + 16),
                      height: ceil(lineHeight * CGFloat(max(1, lines.count))) + 6)
    }
}

struct TextMark: DrawableMark {
    let text: String
    let origin: CGPoint
    let style: MarkAppearance

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func font(for style: MarkAppearance) -> NSFont {
        TextLayout(style: style).font
    }

    func draw(in context: CGContext) {
        let content = TextLayout(style: style).text(text)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        content.draw(at: origin)
    }
}

/// Inline input that grows with the text before it is committed to the canvas.
final class InlineTextEditor: NSTextField {
    static let textInset: CGFloat = 2
    let style: MarkAppearance
    private var layout: TextLayout { TextLayout(style: style) }

    init(style: MarkAppearance) {
        self.style = style
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure() {
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = layout.font
        textColor = style.color
        usesSingleLineMode = false
        lineBreakMode = .byClipping
        cell?.wraps = true
        cell?.isScrollable = false
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
    }

    func fitToText(minimumWidth: CGFloat = 40) {
        setFrameSize(layout.editorSize(for: stringValue, minimumWidth: minimumWidth))
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        (currentEditor() as? NSTextView)?.insertionPointColor = style.color
        return true
    }
}
