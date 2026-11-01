import XCTest
@testable import Rydool

final class LocalizationTests: XCTestCase {
    func testLanguageDefaultsToEnglishAndPersists() throws {
        let suiteName = "RydoolLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .english)
        settings.language = .vietnamese
        XCTAssertEqual(AppSettings(defaults: defaults).language, .vietnamese)
        settings.language = .simplifiedChinese
        XCTAssertEqual(AppSettings(defaults: defaults).language, .simplifiedChinese)
        defaults.set("unknown", forKey: "language")
        XCTAssertEqual(AppSettings(defaults: defaults).language, .english)
    }

    func testTranslationsAndFormattedValues() {
        XCTAssertEqual(Localization.text("Capture Area", language: .english), "Capture Area")
        XCTAssertEqual(Localization.text("Capture Area", language: .vietnamese), "Chụp vùng")
        XCTAssertEqual(Localization.text("Capture Area", language: .simplifiedChinese), "区域截图")
        XCTAssertEqual(Localization.format("Maximum storage: %d MB", language: .simplifiedChinese, arguments: [500]), "最大存储空间：500 MB")
        XCTAssertEqual(Localization.text("Unknown key", language: .vietnamese), "Unknown key")
    }
}
