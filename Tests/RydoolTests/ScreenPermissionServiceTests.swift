import Foundation
import XCTest
@testable import Rydool

final class ScreenPermissionServiceTests: XCTestCase {
    func testRelaunchPassesBundlePathAsAnArgumentBeforeTerminating() throws {
        var actions: [String] = []
        let path = "/Applications/Rydool's test $(example).app"
        let relauncher = AppRelauncher(start: { executable, arguments in
            actions.append("start")
            XCTAssertEqual(executable.path, "/bin/sh")
            XCTAssertEqual(arguments.last, path)
            XCTAssertFalse(arguments[1].contains(path))
        }, terminate: { actions.append("terminate") })

        try relauncher.reopen(bundle: URL(fileURLWithPath: path))
        XCTAssertEqual(actions, ["start", "terminate"])
    }

    func testRelaunchFailureDoesNotTerminateTheApp() {
        var terminated = false
        let relauncher = AppRelauncher(start: { _, _ in
            throw CocoaError(.fileNoSuchFile)
        }, terminate: { terminated = true })

        XCTAssertThrowsError(try relauncher.reopen(bundle: URL(fileURLWithPath: "/Applications/Rydool.app")))
        XCTAssertFalse(terminated)
    }

    func testPermissionCheckDoesNotPromptAndSettingsRequestsBeforeOpening() {
        var actions: [String] = []
        var opened: URL?
        let service = ScreenAccessGateway(
            check: { false },
            request: { actions.append("request") },
            open: { url in opened = url; actions.append("open") }
        )
        XCTAssertFalse(service.isGranted)
        XCTAssertTrue(actions.isEmpty)
        service.openSettings()
        XCTAssertEqual(actions, ["request", "open"])
        XCTAssertEqual(opened?.scheme, "x-apple.systempreferences")
        XCTAssertTrue(opened?.absoluteString.contains("Privacy_ScreenCapture") == true)
    }
}
