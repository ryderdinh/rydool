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
}
