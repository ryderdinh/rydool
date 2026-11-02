import AppKit
import Combine
import SwiftUI

/// Keeps preferences in a normal window, independent of the status-item popover.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let recorder = ShortcutCaptureController()
    private let historyRecorder = ShortcutCaptureController(.history)
    private let fullScreenRecorder = ShortcutCaptureController(.fullScreen)
    private let screenRecordingRecorder = ShortcutCaptureController(.screenRecording)
    private var window: NSWindow?
    private var languageObservation: AnyCancellable?

    func show() {
        LaunchAtLogin.shared.refresh()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Rydool — \(L("Settings"))"
            window.minSize = NSSize(width: 600, height: 420)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: PreferencesView(
                recorder: recorder,
                historyRecorder: historyRecorder,
                fullScreenRecorder: fullScreenRecorder,
                screenRecordingRecorder: screenRecordingRecorder
            ))
            window.center()
            self.window = window
            languageObservation = AppSettings.shared.$language.dropFirst().sink { [weak window] language in
                window?.title = "Rydool — \(Localization.text("Settings", language: language))"
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        recorder.cancel()
        historyRecorder.cancel()
        fullScreenRecorder.cancel()
        screenRecordingRecorder.cancel()
    }
}
