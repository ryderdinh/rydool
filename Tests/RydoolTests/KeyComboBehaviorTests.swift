import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Rydool

final class KeyComboBehaviorTests: XCTestCase {
    func testModifierFilteringCarbonMappingAndDisplayOrder() {
        let combo = ShortcutBinding(keyCode: UInt32(kVK_F8), modifiers: [.control, .option, .shift, .command, .capsLock])
        XCTAssertEqual(combo.modifierFlags, [.control, .option, .shift, .command])
        XCTAssertEqual(combo.carbonModifiers, UInt32(controlKey | optionKey | shiftKey | cmdKey))
        XCTAssertEqual(combo.keyCaps, ["⌃", "⌥", "⇧", "⌘", "F8"])
        XCTAssertTrue(combo.isFunctionKey)
    }

    func testExistingPersistedShortcutFormatIsReadable() throws {
        let data = Data("{\"keyCode\":9,\"modifiers\":655360}".utf8)
        let combo = try JSONDecoder().decode(ShortcutBinding.self, from: data)
        XCTAssertEqual(combo.keyCode, 9)
        XCTAssertEqual(combo.modifierFlags, [.option, .shift])
        let encoded = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: encoded), combo)
    }

    func testUnknownHardwareKeyDoesNotOverflow() {
        let combo = ShortcutBinding(keyCode: UInt32.max, modifiers: [])
        XCTAssertFalse(combo.keySymbol.isEmpty)
    }
}
