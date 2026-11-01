import AppKit
import SwiftUI

struct RecordingOptions {
    let screen: NSScreen
    let area: Bool
    let systemAudio: Bool
    let microphone: Bool
    let resolution: RecordingResolution
    let frameRate: RecordingFrameRate
    let bitrate: RecordingBitrate
}

@MainActor
final class RecordingSetupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onStart: (RecordingOptions) -> Void
    init(onStart: @escaping (RecordingOptions) -> Void) { self.onStart = onStart }

    func show() {
        guard !NSScreen.screens.isEmpty else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 590),
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
    let onCancel: () -> Void
    let onStart: (RecordingOptions) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Record Screen")).font(.system(size: 21, weight: .bold))
                    Text(L("Choose what to capture and how to save it."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("CAPTURE"))
                card {
                    HStack(spacing: 10) {
                        Image(systemName: "display").foregroundStyle(Color.accentColor).frame(width: 22)
                        Text(L("Display")).fontWeight(.medium)
                        Spacer()
                        Picker(L("Display"), selection: $selectedDisplay) {
                            ForEach(NSScreen.screens, id: \.displayID) { screen in
                                if let id = screen.displayID { Text(screen.localizedName).tag(id) }
                            }
                        }.labelsHidden().frame(maxWidth: 230)
                    }
                    Divider()
                    Picker(L("Capture"), selection: $area) {
                        Text(L("Full screen")).tag(false)
                        Text(L("Selected area")).tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("VIDEO QUALITY"))
                card {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Resolution")).fontWeight(.medium)
                            Text(L("Never enlarges the selected area"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(L("Resolution"), selection: $settings.recordingResolution) {
                            ForEach(RecordingResolution.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 135)
                    }
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Frame rate")).fontWeight(.medium)
                            Picker(L("Frame rate"), selection: $settings.recordingFrameRate) {
                                ForEach(RecordingFrameRate.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Quality")).fontWeight(.medium)
                            Picker(L("Quality"), selection: $settings.recordingBitrate) {
                                ForEach(RecordingBitrate.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("AUDIO"))
                card {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2").foregroundStyle(Color.accentColor).frame(width: 22)
                        Toggle(L("System audio"), isOn: $settings.recordingSystemAudio).toggleStyle(.switch).controlSize(.small).accessibilityLabel(L("System audio"))
                    }
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: "mic").foregroundStyle(Color.accentColor).frame(width: 22)
                        Toggle(L("Microphone"), isOn: $settings.recordingMicrophone).toggleStyle(.switch).controlSize(.small).accessibilityLabel(L("Microphone"))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text(L("Saved as MP4")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(area ? L("Select area") : L("Start recording")) {
                    guard let screen = NSScreen.screens.first(where: { $0.displayID == selectedDisplay }) else { return }
                    onStart(RecordingOptions(screen: screen, area: area, systemAudio: settings.recordingSystemAudio, microphone: settings.recordingMicrophone,
                                             resolution: settings.recordingResolution, frameRate: settings.recordingFrameRate,
                                             bitrate: settings.recordingBitrate))
                }.buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 590)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .font(.system(size: 12))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
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
