import AppKit
import SwiftUI

struct RecordingOptions {
    let screen: NSScreen
    let area: Bool
    let systemAudio: Bool
    let microphone: Bool
}

@MainActor
final class RecordingSetupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onStart: (RecordingOptions) -> Void
    init(onStart: @escaping (RecordingOptions) -> Void) { self.onStart = onStart }

    func show() {
        guard !NSScreen.screens.isEmpty else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 360),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("Record Screen")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RecordingSetupView(onCancel: { [weak self] in self?.close() },
            onStart: { [weak self] options in self?.close(); self?.onStart(options) }))
        panel.center()
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func close() { window?.orderOut(nil); window = nil }
    func windowWillClose(_ notification: Notification) { window = nil }
}

private struct RecordingSetupView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedDisplay: CGDirectDisplayID = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.displayID ?? NSScreen.main?.displayID ?? 0
    @State private var area = false
    @State private var systemAudio = true
    @State private var microphone = false
    let onCancel: () -> Void
    let onStart: (RecordingOptions) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Record Screen")).font(.title2.bold())
            Picker(L("Display"), selection: $selectedDisplay) {
                ForEach(NSScreen.screens, id: \.displayID) { screen in
                    if let id = screen.displayID { Text(screen.localizedName).tag(id) }
                }
            }
            Picker(L("Capture"), selection: $area) {
                Text(L("Full screen")).tag(false)
                Text(L("Selected area")).tag(true)
            }.pickerStyle(.segmented)
            Divider()
            Toggle(L("System audio"), isOn: $systemAudio)
            Toggle(L("Microphone"), isOn: $microphone)
            Spacer()
            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(area ? L("Select area") : L("Start recording")) {
                    guard let screen = NSScreen.screens.first(where: { $0.displayID == selectedDisplay }) else { return }
                    onStart(RecordingOptions(screen: screen, area: area, systemAudio: systemAudio, microphone: microphone))
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430, height: 360)
    }
}

/// Drag a single rectangle on the selected display; Escape cancels.
@MainActor
final class RecordingAreaPicker {
    private var window: SelectionWindow?
    func show(on screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        let panel = SelectionWindow(screen: screen)
        let view = RecordingAreaView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self, weak panel] rect in
            panel?.orderOut(nil)
            self?.window = nil
            guard let rect else { completion(nil); return }
            completion(CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY,
                              width: rect.width, height: rect.height))
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = view
        panel.initialFirstResponder = view
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }
    func close() { window?.orderOut(nil); window = nil }
}

private final class RecordingAreaView: NSView {
    private var start: CGPoint?
    private var selection: CGRect = .zero
    private let completion: (CGRect?) -> Void
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(frame: CGRect, completion: @escaping (CGRect?) -> Void) { self.completion = completion; super.init(frame: frame) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selection)
            path.lineWidth = 2
            path.stroke()
        }
        let text = L("Drag to select an area · Esc to cancel") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 30), withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); selection = .zero; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { completion(selection.width >= 10 && selection.height >= 10 ? selection : nil) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { completion(nil) } }
}
