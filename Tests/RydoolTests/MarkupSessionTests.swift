import Foundation
import XCTest
@testable import Rydool

final class MarkupSessionTests: XCTestCase {
    func testAppearanceChangesAreRestoredInANewEditingSession() throws {
        let suite = "Rydool.MarkupSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        let first = MarkupSession(settings: settings)
        first.tool = .arrow
        first.color = .blue
        first.weight = .thick
        first.canUndo = true

        let restored = MarkupSession(settings: AppSettings(defaults: defaults))
        XCTAssertEqual(restored.color, .blue)
        XCTAssertEqual(restored.weight, .thick)
        XCTAssertNil(restored.tool)
        XCTAssertFalse(restored.canUndo)
        XCTAssertEqual(restored.style.lineWidth, LineWeight.thick.lineWidth)
    }
}
