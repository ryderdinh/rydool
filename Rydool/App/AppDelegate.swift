import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: AppRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let runtime = AppRuntime()
            self.runtime = runtime
            runtime.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { RecordingCoordinator.shared.mayQuit() ? .terminateNow : .terminateCancel }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            runtime?.stop()
            runtime = nil
        }
    }
}

/// Owns app-wide services and their registrations for the duration of the process.
@MainActor
private final class AppRuntime {
    private var menuBar: MenuBarController?
    private var languageObserver: NSObjectProtocol?
    private var accessibilityTimer: Timer?

    func start() {
        NSApp.setActivationPolicy(.accessory)
        MainMenu.install()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .rydoolLanguageDidChange, object: nil, queue: .main
        ) { _ in MainMenu.install() }

        let menu = MenuBarController(onCapture: { ScreenshotFlow.shared.start() })
        menuBar = menu
        ScreenshotFlow.shared.willBeginCapture = { [weak menu] in menu?.closePopover() }
        installShortcuts()
        watchAccessibility()
        _ = ClipboardHistory.shared
        DisplaySnapshotService.shared.warmUp()
        #if DEBUG
        if ProcessInfo.processInfo.environment["RYDOOL_TEST_DEFAULTS"] != nil {
            if ProcessInfo.processInfo.environment["RYDOOL_TEST_SHOW_PERMISSIONS"] == "1" {
                SettingsWindowController.shared.show(section: .permissions)
            }
            return
        }
        #endif
        if AppSettings.shared.isFirstLaunch {
            SettingsWindowController.shared.show(section: .permissions)
        }
    }

    func stop() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        languageObserver = nil
        for manager in [GlobalHotkeyManager.shared, .history, .fullScreen, .screenRecording] {
            manager.unregister()
            manager.onTrigger = nil
        }
        ScreenshotFlow.shared.willBeginCapture = nil
        menuBar = nil
    }

    private func watchAccessibility() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard AXIsProcessTrusted() else { return }
            GlobalHotkeyManager.shared.promoteToEventTap()
            GlobalHotkeyManager.fullScreen.promoteToEventTap()
        }
    }

    private func installShortcuts() {
        let settings = AppSettings.shared
        let bindings: [(GlobalHotkeyManager, ShortcutBinding, () -> Void)] = [
            (.shared, settings.shortcut, { MainActor.assumeIsolated { ScreenshotFlow.shared.start() } }),
            (.history, settings.historyShortcut, { MainActor.assumeIsolated { HistoryWindowController.shared.show() } }),
            (.fullScreen, settings.fullScreenShortcut, { MainActor.assumeIsolated { ScreenshotFlow.shared.start(fullScreen: true) } }),
            (.screenRecording, settings.recordingShortcut, { MainActor.assumeIsolated {
                let recording = RecordingCoordinator.shared
                if recording.phase == .recording { recording.stop() } else { recording.showSetup() }
            } })
        ]
        var unavailable: [String] = []
        for (manager, combo, action) in bindings {
            manager.onTrigger = action
            do { try manager.register(combo) }
            catch { unavailable.append(combo.displayString) }
        }
        if !unavailable.isEmpty {
            Alerts.show(title: L("Shortcut unavailable"),
                        message: L("Cannot register %@. Another app may be using these shortcuts. Use the menu or choose different shortcuts in Rydool settings.", unavailable.joined(separator: ", ")))
        }
    }
}

/// Supplies standard text-editing commands for this menu-bar-only application.
enum MainMenu {
    static func install() {
        let main = NSMenu()
        let application = NSMenu()
        application.addItem(withTitle: L("Quit Rydool"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        main.addItem(applicationItem)

        let edit = NSMenu(title: L("Edit"))
        let history: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z")
        ]
        let clipboard: [(String, Selector, String)] = [
            ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")
        ]
        for (title, action, key) in history { edit.addItem(withTitle: L(title), action: action, keyEquivalent: key) }
        edit.addItem(.separator())
        for (title, action, key) in clipboard { edit.addItem(withTitle: L(title), action: action, keyEquivalent: key) }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
