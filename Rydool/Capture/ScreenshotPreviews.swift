import AppKit
import SwiftUI

private let previewSize = CGSize(width: 176, height: 132)

/// Temporarily hides inactive previews while keeping captures available in this session.
@MainActor
final class ScreenshotPreviews: ObservableObject {
    static let shared = ScreenshotPreviews()

    private struct Entry {
        let id: UUID
        let panel: NSPanel
        let screen: NSScreen
        let hoverState: HoverState
        var visible = true
    }
    private var entries: [Entry] = []
    @Published private(set) var hiddenCount = 0
    private var timers: [UUID: Timer] = [:]
    private var hovered = Set<UUID>()
    private var paused = Set<UUID>()
    private var suspended = false
    private let autoHideInterval: TimeInterval = 5
    private let panelSize = previewSize

    func add(_ screenshot: RenderedScreenshot, source: String?, screen: NSScreen?, edit: @escaping (UUID) -> Void) {
        guard let screen = screen ?? NSScreen.main else { return }
        let id = UUID()
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hoverState = HoverState()
        let view = ScreenshotPreviewView(
            screenshot: screenshot,
            hoverState: hoverState,
            edit: { edit(id) },
            copy: { [weak self] in
                do {
                    try ScreenshotClipboard.copy(screenshot, source: source)
                    HUD.show(L("Copied to Clipboard"), symbol: "checkmark.circle.fill")
                    self?.restartTimer(id)
                } catch { Alerts.show(error) }
            },
            save: { [weak self] in
                self?.pauseTimer(id)
                defer { self?.resumeTimer(id) }
                switch ScreenshotExport.presentSavePanel(screenshot) {
                case .saved: HUD.show(L("Saved"), symbol: "checkmark.circle.fill")
                case .cancelled: break
                case .failed(let error): Alerts.show(error)
                }
            },
            dismiss: { [weak self] in self?.remove(id) },
            hover: { [weak self] inside in self?.setHovered(id, inside: inside) }
        )
        panel.contentView = NSHostingView(rootView: view)
        entries.append(Entry(id: id, panel: panel, screen: screen, hoverState: hoverState))
        reposition()
        panel.orderFrontRegardless()
        restartTimer(id)
    }

    func hideAll() {
        suspended = true
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        hovered.removeAll()
        entries.forEach { $0.hoverState.isHovering = false; $0.panel.orderOut(nil) }
    }

    func showAll() {
        suspended = false
        reposition()
        for entry in entries where entry.visible {
            entry.panel.orderFrontRegardless()
            restartTimer(entry.id)
        }
    }

    func showRecent() {
        guard !suspended else { return }
        for index in entries.indices { entries[index].visible = true }
        hiddenCount = 0
        showAll()
    }

    func remove(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        timers.removeValue(forKey: id)?.invalidate()
        hovered.remove(id)
        paused.remove(id)
        entries.remove(at: index).panel.orderOut(nil)
        hiddenCount = entries.filter { !$0.visible }.count
        reposition()
    }

    private func restartTimer(_ id: UUID) {
        timers.removeValue(forKey: id)?.invalidate()
        guard !suspended, !hovered.contains(id), !paused.contains(id),
              entries.contains(where: { $0.id == id && $0.visible }) else { return }
        let timer = Timer(timeInterval: autoHideInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.autoHide(id) }
        }
        timers[id] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func autoHide(_ id: UUID) {
        timers.removeValue(forKey: id)?.invalidate()
        guard !suspended, !hovered.contains(id), !paused.contains(id),
              let index = entries.firstIndex(where: { $0.id == id && $0.visible }) else { return }
        entries[index].visible = false
        entries[index].hoverState.isHovering = false
        entries[index].panel.orderOut(nil)
        hiddenCount = entries.filter { !$0.visible }.count
        reposition()
    }

    private func setHovered(_ id: UUID, inside: Bool) {
        if inside { hovered.insert(id) } else { hovered.remove(id) }
        restartTimer(id)
    }

    private func pauseTimer(_ id: UUID) {
        paused.insert(id)
        timers.removeValue(forKey: id)?.invalidate()
    }

    private func resumeTimer(_ id: UUID) {
        paused.remove(id)
        restartTimer(id)
    }

    private func reposition() {
        let margin: CGFloat = 12
        var counts: [CGDirectDisplayID: Int] = [:]
        for entry in entries.reversed() where entry.visible {
            let screen = NSScreen.screens.first(where: { $0.displayID == entry.screen.displayID }) ?? NSScreen.main ?? entry.screen
            let id = screen.displayID ?? CGMainDisplayID()
            let index = counts[id, default: 0]
            counts[id] = index + 1
            let bounds = screen.visibleFrame
            let rows = max(1, Int((bounds.height - margin) / (panelSize.height + margin)))
            let column = index / rows
            let row = index % rows
            let x = max(bounds.minX, bounds.maxX - panelSize.width - margin - CGFloat(column) * (panelSize.width + margin))
            let y = bounds.minY + margin + CGFloat(row) * (panelSize.height + margin)
            entry.panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

private struct ScreenshotPreviewView: View {
    @ObservedObject private var languageSettings = AppSettings.shared
    let screenshot: RenderedScreenshot
    @ObservedObject var hoverState: HoverState
    let edit: () -> Void
    let copy: () -> Void
    let save: () -> Void
    let dismiss: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: edit) {
            Image(decorative: screenshot.image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Edit screenshot"))
        .accessibilityAction(named: Text(L("Copy")), copy)
        .accessibilityAction(named: Text(L("Save")), save)
        .accessibilityAction(named: Text(L("Close preview")), dismiss)
        .help(L("Edit screenshot"))
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18)))
        .overlay(alignment: .topTrailing) {
            if hoverState.isHovering {
                PreviewIconButton(symbol: "xmark", label: L("Close preview"), action: dismiss)
                    .background(.black.opacity(0.72), in: Circle())
                    .padding(7)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hoverState.isHovering {
                HStack(spacing: 2) {
                    PreviewIconButton(symbol: "pencil", label: L("Edit"), action: edit)
                    PreviewIconButton(symbol: "doc.on.doc", label: L("Copy"), action: copy)
                    PreviewIconButton(symbol: "square.and.arrow.down", label: L("Save"), action: save)
                }
                .padding(3)
                .modifier(PreviewControlsSurface())
                .padding(7)
            }
        }
        .onHover { inside in
            hoverState.isHovering = inside
            hover(inside)
        }
    }
}

private struct PreviewControlsSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .environment(\.colorScheme, .dark)
        } else {
            content.background(.black.opacity(0.72), in: Capsule())
        }
    }
}

private struct PreviewIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
