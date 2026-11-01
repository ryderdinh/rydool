import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Rydool

final class ShortcutValidationBehaviorTests: XCTestCase {
    private func combo(_ key: Int, _ flags: NSEvent.ModifierFlags = []) -> ShortcutBinding {
        ShortcutBinding(keyCode: UInt32(key), modifiers: flags)
    }

    func testRejectsTypingAndReservedKeys() {
        let invalid = [combo(kVK_ANSI_A), combo(kVK_ANSI_C, .command),
                       combo(kVK_Tab, [.command, .shift]), combo(kVK_Escape, .option),
                       combo(kVK_Command, .command)]
        for choice in invalid {
            guard case .invalid = ShortcutValidator.validate(choice, systemShortcutExists: { _ in false }) else {
                return XCTFail("Expected an invalid shortcut: \(choice.keyCode)")
            }
        }
    }

    func testAcceptsFunctionOrModifiedKeyAndReportsSystemConflicts() {
        let choices = [combo(kVK_F8), combo(kVK_ANSI_J, [.control, .option])]
        for choice in choices {
            XCTAssertEqual(ShortcutValidator.validate(choice, systemShortcutExists: { _ in false }), .ok)
            guard case .warning = ShortcutValidator.validate(choice, systemShortcutExists: { _ in true }) else {
                return XCTFail("Expected a system shortcut warning")
            }
        }
        guard case .warning = ShortcutValidator.validate(.default, systemShortcutExists: { _ in false }) else {
            return XCTFail("Expected a screenshot shortcut warning")
        }
    }
}
