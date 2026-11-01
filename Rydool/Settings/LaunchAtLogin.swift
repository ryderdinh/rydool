import AppKit
import Combine
import ServiceManagement

/// The service boundary lets settings reflect actual macOS approval state.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func enable() throws
    func disable() throws
    func openSettings()
}

private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func enable() throws { try SMAppService.mainApp.register() }
    func disable() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin(service: SystemLoginItemService())
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published var errorMessage: String?

    private let service: any LoginItemService
    private let defaults: UserDefaults
    private let runningAsApp: () -> Bool
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"
    var isAvailable: Bool { runningAsApp() }

    init(service: any LoginItemService, defaults: UserDefaults = .standard,
         runningAsApp: @escaping () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" }) {
        self.service = service
        self.defaults = defaults
        self.runningAsApp = runningAsApp
        refresh()
    }

    func refresh() {
        isEnabled = service.status == .enabled
        needsApproval = service.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled { try service.enable() } else { try service.disable() }
        } catch {
            errorMessage = isAvailable
                ? L("Couldn't change the login item. Try again from System Settings › General › Login Items.")
                : L("Launch at Login works when Rydool runs as an app (build it with Scripts/build-app.sh).")
        }
        refresh()
    }

    func openLoginItemsSettings() { service.openSettings() }

    func applyDefaultOnFirstLaunch() {
        guard isAvailable, !defaults.bool(forKey: Self.defaultAppliedKey) else { return }
        defaults.set(true, forKey: Self.defaultAppliedKey)
        if !isEnabled { setEnabled(true) }
    }
}
