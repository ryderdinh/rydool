import AppKit
import Combine
import SwiftUI

/// A normal, movable window containing only the captured image and its tools.
@MainActor
final class ScreenshotEditor: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: SelectionCanvas
    private let originalPointSize: CGSize
    private let onFinish: (RenderedScreenshot, CaptureOutput) -> Void
    private let onCancel: () -> Void
    private var languageObservation: AnyCancellable?

    init(screenshot: RenderedScreenshot, screen: NSScreen?,
         onFinish: @escaping (RenderedScreenshot, CaptureOutput) -> Void,
         onCancel: @escaping () -> Void) {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let original = screenshot.pointSize
        let maxWidth = max(1, visible.width - 100)
        let maxHeight = max(1, visible.height - 160)
        let scale = min(1, maxWidth / max(original.width, 1), maxHeight / max(original.height, 1))
        let canvasSize = CGSize(width: max(1, original.width * scale), height: max(1, original.height * scale))
        let contentSize = CGSize(width: min(visible.width - 40, max(620, canvasSize.width + 24)),
                                 height: min(visible.height - 40, max(320, canvasSize.height + 78)))
        let origin = CGPoint(x: visible.midX - contentSize.width / 2, y: visible.midY - contentSize.height / 2)
        window = NSWindow(contentRect: CGRect(origin: origin, size: contentSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let tools = MarkupSession()
        canvas = SelectionCanvas(frame: CGRect(origin: .zero, size: canvasSize), image: screenshot.image, toolState: tools)
        originalPointSize = original
        self.onFinish = onFinish
        self.onCancel = onCancel
        super.init()

        window.title = "Rydool — \(L("Screenshot"))"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: min(520, visible.width), height: min(300, visible.height))
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]

        let content = NSView(frame: CGRect(origin: .zero, size: contentSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let scroll = NSScrollView(frame: CGRect(x: 12, y: 12, width: contentSize.width - 24, height: contentSize.height - 66))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.contentView = CenteredImageClipView()
        canvas.prepareAsImageEditor()
        canvas.onEditorFinish = { [weak self] output in self?.finish(output) }
        canvas.onEditorCancel = { [weak self] in self?.onCancel() }
        scroll.documentView = canvas
        content.addSubview(scroll)

        let toolbar = MarkupToolbar(state: tools, primaryAction: .copy,
            onUndo: { [weak canvas] in canvas?.undo(); canvas?.focusCanvas() },
            onCancel: { [weak self] in self?.onCancel() },
            onSave: { [weak self] in self?.finish(.saveAs) },
            onPrimary: { [weak self] in self?.finish(.copy) },
            onInteraction: { [weak canvas] in canvas?.focusCanvas() })
        let host = NSHostingView(rootView: toolbar)
        host.frame = CGRect(x: 8, y: contentSize.height - 48, width: contentSize.width - 16, height: 42)
        host.autoresizingMask = [.width, .minYMargin]
        content.addSubview(host)
        window.contentView = content
        window.initialFirstResponder = canvas
        languageObservation = AppSettings.shared.$language.dropFirst().sink { [weak window, weak canvas] language in
            window?.title = "Rydool — \(Localization.text("Screenshot", language: language))"
            canvas?.setAccessibilityLabel(Localization.text("Screenshot canvas", language: language))
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    func hide() { window.orderOut(nil) }

    func close() {
        window.delegate = nil
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancel()
        return false
    }

    private func finish(_ output: CaptureOutput) {
        guard let rendered = canvas.renderScreenshot() else {
            Alerts.show(title: L("Couldn't export image"), message: L("Please try again."))
            return
        }
        onFinish(RenderedScreenshot(image: rendered.image, pointSize: originalPointSize), output)
    }
}

private final class CenteredImageClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let imageFrame = documentView?.frame else { return bounds }
        if imageFrame.width < bounds.width { bounds.origin.x = imageFrame.minX - (bounds.width - imageFrame.width) / 2 }
        if imageFrame.height < bounds.height { bounds.origin.y = imageFrame.minY - (bounds.height - imageFrame.height) / 2 }
        return bounds
    }
}
