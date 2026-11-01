import AppKit
import Combine

enum Alerts {
    static func show(_ error: Error) {
        let description = (error as? LocalizedError)?.errorDescription
            ?? L("Something went wrong. Please try again.")
        show(title: "Rydool", message: description)
    }

    static func show(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Presents a short, noninteractive confirmation without activating the app.
enum HUD {
    private static let presenter = HUDPresenter()
    static func show(_ message: String, symbol: String) { presenter.show(message, symbol: symbol) }
    static func dismiss() { presenter.dismiss() }
}

private final class HUDPresenter {
    private var panel: NSPanel?
    private var pendingDismissal: DispatchWorkItem?

    func show(_ message: String, symbol: String) {
        dismiss()
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .systemGreen
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        let size = row.fittingSize
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.masksToBounds = true
        row.frame = background.bounds
        row.autoresizingMask = [.width, .height]
        background.addSubview(row)

        let bubble = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.contentView = background
        bubble.isOpaque = false
        bubble.backgroundColor = .clear
        bubble.hasShadow = true
        bubble.level = .statusBar
        bubble.ignoresMouseEvents = true
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            bubble.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
        }
        panel = bubble
        bubble.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self, weak bubble] in
            guard let self, let bubble, self.panel === bubble else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.dismiss()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                bubble.animator().alphaValue = 0
            } completionHandler: { [weak self, weak bubble] in
                guard let self, let bubble, self.panel === bubble else { return }
                self.dismiss()
            }
        }
        pendingDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    func dismiss() {
        pendingDismissal?.cancel()
        pendingDismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

final class HoverState: ObservableObject {
    @Published var isHovering = false
}
