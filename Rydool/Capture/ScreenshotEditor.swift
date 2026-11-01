import AppKit
import Combine
import SwiftUI

/// A normal, movable window containing only the captured image and its tools.
@MainActor
final class ScreenshotEditor: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let canvas: SelectionCanvas
    private let scroll: NSScrollView
    private let zoom = EditorZoomState()
    private var zoomObservation: NSKeyValueObservation?
    private var magnifyObservation: NSObjectProtocol?
    private var fitsWindow = true
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
        let maxHeight = max(1, visible.height - 220)
        let scale = min(1, maxWidth / max(original.width, 1), maxHeight / max(original.height, 1))
        let canvasSize = CGSize(width: max(1, original.width * scale), height: max(1, original.height * scale))
        let contentSize = CGSize(width: min(visible.width - 40, max(620, canvasSize.width + 24)),
                                 height: min(visible.height - 40, max(360, canvasSize.height + 140)))
        let origin = CGPoint(x: visible.midX - contentSize.width / 2, y: visible.midY - contentSize.height / 2)
        window = NSWindow(contentRect: CGRect(origin: origin, size: contentSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let tools = MarkupSession()
        canvas = SelectionCanvas(frame: CGRect(origin: .zero, size: original), image: screenshot.image, toolState: tools)
        scroll = NSScrollView()
        originalPointSize = original
        self.onFinish = onFinish
        self.onCancel = onCancel
        super.init()

        window.title = "Rydool — \(L("Screenshot"))"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: min(560, visible.width), height: min(340, visible.height))
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]

        let content = NSView(frame: CGRect(origin: .zero, size: contentSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        scroll.frame = CGRect(x: 16, y: 58, width: contentSize.width - 32, height: contentSize.height - 128)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 4
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.masksToBounds = true
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor
        scroll.contentView = CenteredImageClipView()
        canvas.prepareAsImageEditor()
        canvas.onEditorFinish = { [weak self] output in self?.finish(output) }
        canvas.onEditorCancel = { [weak self] in self?.onCancel() }
        scroll.documentView = canvas
        content.addSubview(scroll)

        let toolbar = EditorToolbar(state: tools,
            onUndo: { [weak canvas] in canvas?.undo(); canvas?.focusCanvas() },
            onInteraction: { [weak canvas] in canvas?.focusCanvas() })
        let host = NSHostingView(rootView: toolbar)
        host.frame = CGRect(x: 16, y: contentSize.height - 62, width: contentSize.width - 32, height: 54)
        host.autoresizingMask = [.width, .minYMargin]
        content.addSubview(host)
        let zoomBar = NSHostingView(rootView: EditorFooter(state: zoom,
            onZoomOut: { [weak self] in self?.changeZoom(by: 1 / 1.25) },
            onZoomIn: { [weak self] in self?.changeZoom(by: 1.25) },
            onActualSize: { [weak self] in self?.setZoom(1) },
            onFit: { [weak self] in self?.fitImage() },
            onCancel: { [weak self] in self?.onCancel() },
            onSave: { [weak self] in self?.finish(.saveAs) },
            onCopy: { [weak self] in self?.finish(.copy) }))
        zoomBar.frame = CGRect(x: 16, y: 5, width: contentSize.width - 32, height: 48)
        zoomBar.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(zoomBar)
        window.contentView = content
        window.initialFirstResponder = canvas
        zoomObservation = scroll.observe(\.magnification, options: [.initial, .new]) { [weak zoom] scroll, _ in
            MainActor.assumeIsolated { zoom?.magnification = scroll.magnification }
        }
        magnifyObservation = NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveMagnifyNotification,
            object: scroll, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fitsWindow = false }
            }
        languageObservation = AppSettings.shared.$language.dropFirst().sink { [weak window, weak canvas] language in
            window?.title = "Rydool — \(Localization.text("Screenshot", language: language))"
            canvas?.setAccessibilityLabel(Localization.text("Screenshot canvas", language: language))
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        fitImage()
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

    func windowDidResize(_ notification: Notification) {
        if fitsWindow { fitImage() }
    }

    deinit {
        if let magnifyObservation { NotificationCenter.default.removeObserver(magnifyObservation) }
    }

    private func changeZoom(by factor: CGFloat) { setZoom(scroll.magnification * factor) }

    private func setZoom(_ value: CGFloat) {
        fitsWindow = false
        let center = CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
        scroll.setMagnification(min(scroll.maxMagnification, max(scroll.minMagnification, value)), centeredAt: center)
        canvas.focusCanvas()
    }

    private func fitImage() {
        fitsWindow = true
        let viewport = scroll.contentView.frame.size
        guard viewport.width > 0, viewport.height > 0, originalPointSize.width > 0, originalPointSize.height > 0 else { return }
        let value = min(1, viewport.width / originalPointSize.width, viewport.height / originalPointSize.height)
        scroll.magnification = max(scroll.minMagnification, value)
        canvas.focusCanvas()
    }

    private func finish(_ output: CaptureOutput) {
        guard let rendered = canvas.renderScreenshot() else {
            Alerts.show(title: L("Couldn't export image"), message: L("Please try again."))
            return
        }
        onFinish(RenderedScreenshot(image: rendered.image, pointSize: originalPointSize), output)
    }
}

@MainActor private final class EditorZoomState: ObservableObject {
    @Published var magnification: CGFloat = 1
}

private struct EditorToolbar: View {
    @ObservedObject var state: MarkupSession
    @ObservedObject private var settings = AppSettings.shared
    let onUndo: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    EditorIconButton(symbol: tool.symbol, label: tool.title,
                                     help: "\(tool.title) (\(tool.key.uppercased()))",
                                     selected: state.tool == tool) {
                        state.tool = state.tool == tool ? nil : tool
                        onInteraction()
                    }
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 24)

            HStack(spacing: 4) {
                ForEach(AnnotationColor.allCases) { color in
                    Button {
                        state.color = color
                        onInteraction()
                    } label: {
                        Circle().fill(Color(nsColor: color.nsColor))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5))
                            .padding(3)
                            .overlay(Circle().strokeBorder(state.color == color ? Color.accentColor : .clear, lineWidth: 2))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L(color.rawValue.capitalized))
                    .accessibilityLabel(L(color.rawValue.capitalized))
                }
            }

            Button {
                state.weight = state.weight.next
                onInteraction()
            } label: {
                Capsule().fill(Color(nsColor: state.color.nsColor))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 17, height: state.weight.lineWidth + 1)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Thickness: %@", state.weight.title))
            .accessibilityLabel(L("Thickness: %@", state.weight.title))

            Spacer(minLength: 0)
            EditorIconButton(symbol: "arrow.uturn.backward", label: L("Undo"),
                             help: L("Undo (⌘Z)"), enabled: state.canUndo, action: onUndo)
        }
    }
}

private struct EditorIconButton: View {
    let symbol: String
    let label: String
    let help: String
    var selected = false
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct EditorFooter: View {
    @ObservedObject var state: EditorZoomState
    @ObservedObject private var settings = AppSettings.shared
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onActualSize: () -> Void
    let onFit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            EditorIconButton(symbol: "minus.magnifyingglass", label: L("Zoom out"), help: L("Zoom out"), action: onZoomOut)
            Button("\(Int((state.magnification * 100).rounded()))%", action: onActualSize)
                .monospacedDigit().frame(width: 46, height: 32)
                .help(L("Actual size")).accessibilityLabel(L("Actual size"))
            EditorIconButton(symbol: "plus.magnifyingglass", label: L("Zoom in"), help: L("Zoom in"), action: onZoomIn)
            Button(L("Fit"), action: onFit)
                .padding(.horizontal, 8).frame(height: 30)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                .help(L("Fit image to window"))
            Spacer(minLength: 8)
            EditorIconButton(symbol: "xmark", label: L("Cancel"), help: L("Cancel (Esc)"), action: onCancel)
            Button(action: onSave) {
                Label(L("Save"), systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            .help(L("Save As… (⌘S)"))
            .accessibilityLabel(L("Save As… (⌘S)"))
            Button(action: onCopy) {
                Label(L("Copy"), systemImage: "doc.on.doc")
                    .fontWeight(.semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .help("\(L("Copy")) (↩)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
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
