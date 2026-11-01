import ServiceManagement
import XCTest
@testable import Rydool

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var enableCalls = 0
    var disableCalls = 0
    var shouldFail = false
    var nextStatus: SMAppService.Status = .enabled
    func enable() throws {
        enableCalls += 1
        if shouldFail { throw NSError(domain: "test", code: 1) }
        status = nextStatus
    }
    func disable() throws {
        disableCalls += 1
        if shouldFail { throw NSError(domain: "test", code: 2) }
        status = .notRegistered
    }
    func openSettings() {}
}

final class LaunchAtLoginTests: XCTestCase {
    func testDefaultRunsOnceAndReportsApproval() throws {
        let suite = "rydool-login-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.nextStatus = .requiresApproval
        let controller = LaunchAtLogin(service: service, defaults: defaults, runningAsApp: { true })
        controller.applyDefaultOnFirstLaunch()
        controller.applyDefaultOnFirstLaunch()
        XCTAssertEqual(service.enableCalls, 1)
        XCTAssertTrue(controller.needsApproval)
        XCTAssertFalse(controller.isEnabled)
    }

    func testFailureAndUnavailableAppLeaveActualStatusVisible() throws {
        let suite = "rydool-login-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FakeLoginItemService()
        service.shouldFail = true
        let controller = LaunchAtLogin(service: service, defaults: defaults, runningAsApp: { false })
        controller.applyDefaultOnFirstLaunch()
        XCTAssertEqual(service.enableCalls, 0)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNotNil(controller.errorMessage)
    }
}
