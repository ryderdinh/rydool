import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A borderless window for selecting an area on one display.
final class SelectionWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum CaptureOutput {
    case primary, copy, saveAs
}

/// Displays the frozen image and translates user input into capture gestures.
final class SelectionCanvas: NSView, NSTextFieldDelegate {
    weak var coordinator: ScreenshotFlow?
    let screenImage: CGImage
    var automaticallyFinishSelection = true
    var onEditorFinish: ((CaptureOutput) -> Void)?
    var onEditorCancel: (() -> Void)?

    private let tools: MarkupSession
    private var selection: SelectionManager
    private var gesture: CaptureGesture = .idle
    private var editingImage = false
    private let imageView = NSImageView()
    private let marks = MarkupCanvas()
    private let chrome = SelectionChromeView()
    private var toolbar: NSHostingView<MarkupToolbar>?
    private var input: InlineTextEditor?
    private var pointerTracking: NSTrackingArea?
    private var observers = Set<AnyCancellable>()

    var hasSelection: Bool { selection.rect != nil }
    var hasAnnotations: Bool { marks.hasAnnotations }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, image: CGImage, toolState: MarkupSession) {
        screenImage = image
        tools = toolState
        selection = SelectionManager(bounds: CGRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        wantsLayer = true
        imageView.image = NSImage(cgImage: image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        for child in [imageView, marks, chrome] as [NSView] {
            child.frame = bounds
            child.autoresizingMask = [.width, .height]
            addSubview(child)
        }
        tools.$tool.dropFirst().sink { [weak self] _ in
            self?.commitTextEditing()
            self?.updateCursor()
        }.store(in: &observers)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func selectFullScreen(showToolbar: Bool = true) {
        selection.set(bounds)
        updateSelectionUI()
        if showToolbar { positionToolbar() }
    }

    func prepareAsImageEditor() {
        editingImage = true
        automaticallyFinishSelection = false
        chrome.isHidden = true
        selection.set(bounds)
        updateSelectionUI()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Screenshot canvas"))
    }

    func focusCanvas() {
        if input == nil { window?.makeFirstResponder(self) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let input, input.frame.contains(local) { return input.hitTest(local) ?? input }
        if let toolbar, !toolbar.isHidden, toolbar.frame.contains(local) { return toolbar.hitTest(local) }
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        if input != nil { commitTextEditing(); return }
        window?.makeFirstResponder(self)

        if let area = selection.rect {
            if !editingImage, let handle = selection.handle(at: point) {
                gesture = .resize(handle: handle, origin: area, pointer: point)
                toolbar?.isHidden = true
                return
            }
            if area.contains(point), let tool = tools.tool {
                if tool == .text { beginText(at: point) }
                else { marks.begin(tool, at: point, style: tools.style); gesture = .annotation }
                return
            }
            if area.contains(point), tools.tool == nil {
                guard !editingImage else { return }
                if event.clickCount == 2 { finish(.primary); return }
                gesture = .move(origin: area, pointer: point)
                NSCursor.closedHand.set()
                toolbar?.isHidden = true
                return
            }
            if marks.hasAnnotations { return }
        }

        guard coordinator?.allowSelection(self) ?? true else { return }
        selection.clear()
        gesture = .selection(anchor: point)
        toolbar?.isHidden = true
        updateSelectionUI()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if case .annotation = gesture { marks.update(to: point); return }
        guard let updated = gesture.selection(at: point, in: selection) else { return }
        selection.set(updated)
        updateSelectionUI()
    }

    override func mouseUp(with event: NSEvent) {
        let created = gesture.isSelecting
        switch gesture {
        case .selection:
            let area = selection.rect ?? .zero
            if area.width < SelectionManager.minimumSize || area.height < SelectionManager.minimumSize {
                selection.set(bounds)
            }
        case .annotation:
            marks.end()
            tools.canUndo = marks.hasAnnotations
        default:
            break
        }
        gesture = .idle
        updateSelectionUI()
        if created && automaticallyFinishSelection, let coordinator {
            coordinator.completeSelection(from: self)
            return
        }
        if !editingImage { positionToolbar() }
        updateCursor()
    }

    override func rightMouseDown(with event: NSEvent) {
        if !editingImage { cancel() }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(ShortcutBinding.supportedModifiers)
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if hasSelection { finish(.primary) }
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            if !editingImage { moveSelection(keyCode: Int(event.keyCode), distance: flags.contains(.shift) ? 10 : 1) }
        default:
            guard flags.isEmpty, hasSelection,
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  let tool = AnnotationTool.allCases.first(where: { $0.key == key }) else { return }
            tools.tool = tools.tool == tool ? nil : tool
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(ShortcutBinding.supportedModifiers) == [.command] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": undo()
        case "c": if hasSelection { finish(.copy) }
        case "s": if hasSelection { finish(.saveAs) }
        case "w": cancel()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    func undo() {
        if input != nil { discardText(); return }
        marks.undo()
        tools.canUndo = marks.hasAnnotations
    }

    func clearSelection() {
        commitTextEditing()
        selection.clear()
        gesture = .idle
        toolbar?.isHidden = true
        updateSelectionUI()
    }

    private func moveSelection(keyCode: Int, distance: CGFloat) {
        guard let area = selection.rect else { return }
        let vectors: [Int: CGSize] = [
            kVK_LeftArrow: CGSize(width: -distance, height: 0),
            kVK_RightArrow: CGSize(width: distance, height: 0),
            kVK_UpArrow: CGSize(width: 0, height: -distance),
            kVK_DownArrow: CGSize(width: 0, height: distance)
        ]
        guard let delta = vectors[keyCode] else { return }
        selection.set(selection.moved(area, by: delta))
        updateSelectionUI()
        positionToolbar()
    }

    private func updateSelectionUI() {
        chrome.selection = selection.rect
        chrome.showsHandles = selection.rect != nil && !gesture.isSelecting
        marks.clipRect = selection.rect
    }

    private func finish(_ output: CaptureOutput) {
        if let onEditorFinish { onEditorFinish(output) }
        else { coordinator?.finish(output, from: self) }
    }

    private func cancel() {
        if let onEditorCancel { onEditorCancel() }
        else { coordinator?.cancel() }
    }

    private func makeToolbar() -> NSHostingView<MarkupToolbar> {
        let controls = MarkupToolbar(state: tools, primaryAction: .copy,
            onUndo: { [weak self] in self?.undo(); self?.focusCanvas() },
            onCancel: { [weak self] in self?.coordinator?.cancel() },
            onSave: { [weak self] in
                guard let self else { return }
                self.coordinator?.finish(.saveAs, from: self)
            }, onPrimary: { [weak self] in
                guard let self else { return }
                self.coordinator?.finish(.primary, from: self)
            }, onInteraction: { [weak self] in self?.focusCanvas() })
        let host = NSHostingView(rootView: controls)
        host.isHidden = true
        addSubview(host)
        toolbar = host
        return host
    }

    private func positionToolbar() {
        guard let area = selection.rect else { toolbar?.isHidden = true; return }
        let host = toolbar ?? makeToolbar()
        let size = host.fittingSize
        let margin: CGFloat = 8
        let below = area.maxY + margin
        let above = area.minY - margin - size.height
        let y: CGFloat
        if below + size.height <= bounds.maxY - margin { y = below }
        else if above >= bounds.minY + margin { y = above }
        else { y = area.maxY - margin - size.height }
        let x = min(max(area.maxX - size.width, bounds.minX + margin), bounds.maxX - size.width - margin)
        host.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        host.isHidden = false
    }

    private func beginText(at point: CGPoint) {
        let field = InlineTextEditor(style: tools.style)
        field.delegate = self
        let height = ceil(field.fittingSize.height)
        field.frame = CGRect(x: point.x - InlineTextEditor.textInset, y: point.y - height / 2, width: 40, height: height)
        field.fitToText()
        if let toolbar { addSubview(field, positioned: .below, relativeTo: toolbar) }
        else { addSubview(field) }
        input = field
        window?.makeFirstResponder(field)
        updateCursor()
    }

    func commitTextEditing() {
        guard let field = input else { return }
        input = nil
        let mark = TextMark(text: field.stringValue,
                                  origin: CGPoint(x: field.frame.minX + InlineTextEditor.textInset, y: field.frame.minY),
                                  style: field.style)
        window?.makeFirstResponder(self)
        field.removeFromSuperview()
        marks.add(mark)
        tools.canUndo = marks.hasAnnotations
    }

    private func discardText() {
        guard let field = input else { return }
        input = nil
        window?.makeFirstResponder(self)
        field.removeFromSuperview()
    }

    func controlTextDidChange(_ notification: Notification) { input?.fitToText() }
    func controlTextDidEndEditing(_ notification: Notification) { commitTextEditing() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditing()
            return true
        }
        return false
    }

    func renderScreenshot() -> RenderedScreenshot? {
        commitTextEditing()
        guard let area = selection.rect, area.width >= 1, area.height >= 1 else { return nil }
        return ScreenshotRenderer.render(image: screenImage, viewSize: bounds.size, selection: area, annotations: marks.annotations)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }

    override func mouseMoved(with event: NSEvent) { setCursor(at: convert(event.locationInWindow, from: nil)) }
    override func cursorUpdate(with event: NSEvent) { setCursor(at: convert(event.locationInWindow, from: nil)) }

    func updateCursor() {
        guard let window else { return }
        setCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func setCursor(at point: CGPoint) {
        let cursor: NSCursor
        if let toolbar, !toolbar.isHidden, toolbar.frame.contains(point) { cursor = .arrow }
        else if let input, input.frame.contains(point) { cursor = .iBeam }
        else if let area = selection.rect {
            if !editingImage, let handle = selection.handle(at: point) { cursor = handle.cursor }
            else if area.contains(point) {
                switch tools.tool {
                case .text: cursor = .iBeam
                case .some: cursor = .crosshair
                case .none: cursor = editingImage ? .arrow : .openHand
                }
            } else { cursor = marks.hasAnnotations ? .arrow : .crosshair }
        } else { cursor = .crosshair }
        cursor.set()
    }
}
