import AppKit
import SwiftUI
import Combine

final class PermissionStatus: ObservableObject {
    @Published var isGranted = ScreenAccess.isGranted
    func refresh() { isGranted = ScreenAccess.isGranted }
}

/// Coordinates the status item, its menu, and focus-sensitive actions.
final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSPopover()
    private let permission = PermissionStatus()
    private var animator: StatusItemAnimator?
    private var previousApp: NSRunningApplication?
    private var recordingObserver: AnyCancellable?

    init(onCapture: @escaping () -> Void) {
        super.init()
        if let button = item.button {
            animator = StatusItemAnimator(button: button)
            button.target = self
            button.action = #selector(toggleMenu)
            button.toolTip = "Rydool"
        }
        let content = MenuBarView(
            permission: permission,
            onHistory: { [weak self] in
                guard let self else { return }
                self.closePopover()
                MainActor.assumeIsolated { HistoryWindowController.shared.show(target: self.previousApp) }
            }, onFullScreen: { [weak self] in
                self?.afterClosing { MainActor.assumeIsolated { ScreenshotFlow.shared.start(fullScreen: true) } }
            }, onCapture: { [weak self] in
                self?.afterClosing(onCapture)
            }, onRecording: { [weak self] in
                self?.afterClosing { MainActor.assumeIsolated {
                    let recording = RecordingCoordinator.shared
                    if recording.phase == .recording { recording.stop() } else { recording.showSetup() }
                } }
            }, onRecentScreenshots: { [weak self] in
                self?.closePopover()
                MainActor.assumeIsolated { ScreenshotPreviews.shared.showRecent() }
            }, onGrantPermission: { [weak self] in
                self?.closePopover()
                MainActor.assumeIsolated { SettingsWindowController.shared.show(section: .permissions) }
            }, onSettings: { [weak self] in
                self?.closePopover()
                MainActor.assumeIsolated { SettingsWindowController.shared.show() }
            }, onQuit: { NSApp.terminate(nil) }
        )
        MainActor.assumeIsolated {
            recordingObserver = RecordingCoordinator.shared.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
                guard let self else { return }
                let active = phase == .recording
                self.item.length = active ? NSStatusItem.variableLength : NSStatusItem.squareLength
                self.item.button?.imagePosition = active ? .imageLeading : .imageOnly
                self.item.button?.attributedTitle = NSAttributedString(string: active ? " ●" : "", attributes: [.foregroundColor: NSColor.systemRed])
            }
        }
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        menu.contentViewController = controller
        menu.behavior = .transient
    }

    private func afterClosing(_ action: @escaping () -> Void) {
        closePopover()
        // Wait for the menu to leave the display before freezing the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
    }

    func closePopover() {
        guard menu.isShown else { return }
        let wasAnimated = menu.animates
        menu.animates = false
        menu.performClose(nil)
        menu.animates = wasAnimated
    }

    @objc private func toggleMenu() {
        animator?.play()
        if menu.isShown { menu.performClose(nil); return }
        guard let button = item.button else { return }
        let foreground = NSWorkspace.shared.frontmostApplication
        previousApp = foreground?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : foreground
        permission.refresh()
        NSApp.activate(ignoringOtherApps: true)
        menu.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        menu.contentViewController?.view.window?.makeKey()
    }
}
