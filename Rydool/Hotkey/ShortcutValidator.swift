import AppKit
import Carbon.HIToolbox

enum ShortcutValidation: Equatable {
    case ok
    case warning(String)
    case invalid(String)
}

/// Evaluates shortcut choices before attempting system registration.
enum ShortcutValidator {
    private static let commonCommandKeys: Set<UInt32> = Set([
        kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z,
        kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_O, kVK_ANSI_N, kVK_ANSI_P, kVK_ANSI_F,
        kVK_ANSI_T, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Comma
    ].map(UInt32.init))

    static func validate(_ combo: ShortcutBinding) -> ShortcutValidation {
        validate(combo, systemShortcutExists: systemShortcutExists)
    }

    /// The system lookup is injected so validation can be tested deterministically.
    static func validate(_ combo: ShortcutBinding, systemShortcutExists: (ShortcutBinding) -> Bool) -> ShortcutValidation {
        let key = combo.keyCode
        let flags = combo.modifierFlags
        if ShortcutBinding.modifierKeyCodes.contains(Int(key)) {
            return .invalid(L("Press a key together with the modifiers."))
        }
        if key == UInt32(kVK_Escape) {
            return .invalid(L("Escape is used to cancel a capture. Choose a different key."))
        }
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        if !combo.isFunctionKey && flags.intersection(commandModifiers).isEmpty {
            return .invalid(L("Include ⌘, ⌥ or ⌃ so the shortcut doesn't get in the way of typing."))
        }
        if flags == .command && commonCommandKeys.contains(key) {
            return .invalid(L("%@ is a standard Mac shortcut used by most apps. Choose a different one.", combo.displayString))
        }
        if flags.contains(.command) && [UInt32(kVK_Tab), UInt32(kVK_Space)].contains(key) {
            return .invalid(L("%@ is reserved by macOS. Choose a different one.", combo.displayString))
        }

        let screenshot = GlobalHotkeyManager.isSystemScreenshot(combo)
        if screenshot || systemShortcutExists(combo) {
            if screenshot {
                return .warning(L("macOS also uses %@ for screenshots. For Rydool capture shortcuts, allow Accessibility access to intercept it.", combo.displayString))
            }
            let feature = screenshot ? L("Screenshots") : L("a system shortcut")
            return .warning(L("macOS also uses %@ for %@. Turn it off in System Settings › Keyboard › Keyboard Shortcuts so Rydool receives it.", combo.displayString, feature))
        }
        return .ok
    }

    private static func systemShortcutExists(_ combo: ShortcutBinding) -> Bool {
        var entries: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&entries) == noErr,
              let shortcuts = entries?.takeRetainedValue() as? [[String: Any]] else { return false }
        let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        for entry in shortcuts {
            guard let enabled = entry["kHISymbolicHotKeyEnabled"] as? Bool, enabled,
                  let code = (entry["kHISymbolicHotKeyCode"] as? NSNumber)?.uint32Value,
                  let modifiers = (entry["kHISymbolicHotKeyModifiers"] as? NSNumber)?.uint32Value else { continue }
            if code == combo.keyCode && modifiers & mask == combo.carbonModifiers { return true }
        }
        return false
    }
}
