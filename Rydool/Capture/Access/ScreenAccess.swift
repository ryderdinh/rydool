import AppKit
import ApplicationServices
import SwiftUI

/// Separates the macOS permission prompt and settings link from the UI.
struct ScreenAccessGateway {
    let check: () -> Bool
    let request: () -> Void
    let open: (URL) -> Void

    var isGranted: Bool { check() }

    func openSettings() {
        request()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        open(url)
    }
}

/// Starts the reopen helper before terminating, so a launch failure leaves the app usable.
struct AppRelauncher {
    let start: (URL, [String]) throws -> Void
    let terminate: () -> Void

    func reopen(bundle: URL) throws {
        if bundle.pathExtension == "app" {
            try start(URL(fileURLWithPath: "/bin/sh"), [
                "-c", "sleep 0.5; exec /usr/bin/open \"$1\"", "rydool-reopen", bundle.path
            ])
        }
        terminate()
    }
}

enum ScreenAccess {
    private static let onboardingKey = "hasShownPermissionOnboarding"
    private static let service = ScreenAccessGateway(
        check: { CGPreflightScreenCaptureAccess() },
        request: { _ = CGRequestScreenCaptureAccess() },
        open: { NSWorkspace.shared.open($0) }
    )
    static var isGranted: Bool { service.isGranted }
    static var hasShownOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }
    static func openSystemSettings() { service.openSettings() }

    /// A newly granted macOS screen-capture permission can require a restart.
    static func relaunch() {
        let relauncher = AppRelauncher(start: { executable, arguments in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            try process.run()
        }, terminate: { NSApp.terminate(nil) })
        do {
            try relauncher.reopen(bundle: Bundle.main.bundleURL)
        } catch {
            Alerts.show(error)
        }
    }
}

final class PermissionWindowController {
    static let shared = PermissionWindowController()
    private var panel: NSWindow?

    func show() {
        if panel == nil { panel = makePanel() }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.close() }

    private func makePanel() -> NSWindow {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PermissionView(close: { [weak self] in self?.close() }))
        panel.center()
        return panel
    }
}

private struct PermissionView: View {
    @ObservedObject private var languageSettings = AppSettings.shared
    let close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            icon
            explanation
            actions
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 380)
    }

    private var icon: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.accentColor.gradient))
    }

    private var explanation: some View {
        VStack(spacing: 6) {
            Text(L("Rydool needs Screen Recording permission\nto capture your screen."))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(L("Turn on Rydool in System Settings, then reopen Rydool. Screenshots never leave your Mac."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: ScreenAccess.openSystemSettings) {
                Text(L("Open System Settings")).frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            HStack {
                Button(L("Not Now"), action: close).buttonStyle(.borderless)
                Spacer()
                Button(L("Reopen Rydool"), action: ScreenAccess.relaunch).buttonStyle(.borderless)
            }
            .font(.callout)
        }
    }
}
