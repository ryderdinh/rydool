import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Rydool

final class ShortcutTests: XCTestCase {
    func testCaptureDefaultShortcuts() {
        XCTAssertEqual(ShortcutBinding.default.keyCode, UInt32(kVK_ANSI_4))
        XCTAssertEqual(ShortcutBinding.fullScreenDefault.keyCode, UInt32(kVK_ANSI_3))
        XCTAssertEqual(ShortcutBinding.default.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(ShortcutBinding.fullScreenDefault.carbonModifiers, UInt32(cmdKey | shiftKey))
    }

    func testSystemScreenshotShortcutMatching() {
        XCTAssertTrue(GlobalHotkeyManager.isSystemScreenshot(.default))
        XCTAssertTrue(GlobalHotkeyManager.isSystemScreenshot(.fullScreenDefault))
        XCTAssertTrue(GlobalHotkeyManager.isSystemScreenshot(ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift, .control])))
        XCTAssertFalse(GlobalHotkeyManager.isSystemScreenshot(ShortcutBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift, .control])))
        XCTAssertFalse(GlobalHotkeyManager.isSystemScreenshot(ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .option])))
    }
}
