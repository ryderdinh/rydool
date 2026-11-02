import AppKit
import ApplicationServices
import AVFoundation

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

/// Clears only this app's saved decision, allowing macOS to ask again.
enum PermissionReset {
    enum Service: String {
        case screenRecording = "ScreenCapture"
        case accessibility = "Accessibility"
        case microphone = "Microphone"
    }

    static func reset(_ service: Service) throws {
        guard let identifier = Bundle.main.bundleIdentifier else { throw ResetError.unavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service.rawValue, identifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw ResetError.unavailable }
    }

    enum ResetError: Error { case unavailable }
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
    private static let service = ScreenAccessGateway(
        check: { CGPreflightScreenCaptureAccess() },
        request: { _ = CGRequestScreenCaptureAccess() },
        open: { NSWorkspace.shared.open($0) }
    )
    static var isGranted: Bool { service.isGranted }
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

enum AccessibilityAccess {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func openSystemSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum MicrophoneAccess {
    static var isGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    static func openSystemSettings() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
