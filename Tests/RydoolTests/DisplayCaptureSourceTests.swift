import AppKit
import XCTest
@testable import Rydool

@MainActor
private final class FakeDisplaySource: DisplaySnapshotSource {
    var invalidations = 0
    var attempts = 0
    var failures: [Error] = []

    func prepare() async throws {}
    func invalidate() { invalidations += 1 }
    func capture() async throws -> [DisplaySnapshot] {
        attempts += 1
        if !failures.isEmpty { throw failures.removeFirst() }
        return []
    }
}

final class DisplayCaptureSourceTests: XCTestCase {
    @MainActor
    func testCaptureRetriesOnceAfterDisplayFailure() async throws {
        let source = FakeDisplaySource()
        source.failures = [SnapshotFailure.noDisplays]
        let manager = DisplaySnapshotService(source: source)
        _ = try await manager.captureDisplays()
        XCTAssertEqual(source.attempts, 2)
        XCTAssertEqual(source.invalidations, 1)
    }

    @MainActor
    func testCaptureDoesNotRetryPermissionDenial() async {
        let source = FakeDisplaySource()
        source.failures = [SnapshotFailure.permissionDenied]
        let manager = DisplaySnapshotService(source: source)
        do {
            _ = try await manager.captureDisplays()
            XCTFail("Expected permission denial")
        } catch SnapshotFailure.permissionDenied {
            XCTAssertEqual(source.attempts, 1)
            XCTAssertEqual(source.invalidations, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
