import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Rydool

final class AppSettingsPersistenceTests: XCTestCase {
    func testExistingShortcutsAndAppearanceSurviveReload() throws {
        let suite = "rydool-settings-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: [.control, .option])
        defaults.set(try JSONEncoder().encode(original), forKey: "shortcut")
        defaults.set(AnnotationColor.blue.rawValue, forKey: "annotationColor")
        defaults.set(LineWeight.thick.rawValue, forKey: "annotationLineWeight")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut, original)
        XCTAssertEqual(settings.annotationColor, .blue)
        XCTAssertEqual(settings.lineWeight, .thick)
        let updated = ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .option])
        settings.historyShortcut = updated
        settings.annotationColor = .green
        settings.lineWeight = .thin
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.historyShortcut, updated)
        XCTAssertEqual(restored.annotationColor, .green)
        XCTAssertEqual(restored.lineWeight, .thin)
    }

    func testInvalidStoredShortcutFallsBackToDefault() throws {
        let suite = "rydool-settings-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "shortcut")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcut, .default)
        XCTAssertEqual(settings.lineWeight, .medium)
    }
}
