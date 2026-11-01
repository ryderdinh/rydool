import AppKit
import Carbon.HIToolbox

/// A hardware key and the modifier keys held with it.
struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt

    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let `default` = ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift])
    static let historyDefault = ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option, .shift])
    static let fullScreenDefault = ShortcutBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift])

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    private static let modifierMapping: [(NSEvent.ModifierFlags, UInt32, String)] = [
        (.control, UInt32(controlKey), "⌃"), (.option, UInt32(optionKey), "⌥"),
        (.shift, UInt32(shiftKey), "⇧"), (.command, UInt32(cmdKey), "⌘")
    ]

    var carbonModifiers: UInt32 {
        Self.modifierMapping.reduce(0) { result, entry in
            modifierFlags.contains(entry.0) ? result | entry.1 : result
        }
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        modifierMapping.compactMap { flags.contains($0.0) ? $0.2 : nil }
    }

    var keyCaps: [String] { Self.modifierSymbols(modifierFlags) + [keySymbol] }
    var displayString: String { keyCaps.joined() }
    var isFunctionKey: Bool { ShortcutKeyNames.functionNames[Int(keyCode)] != nil }

    var keySymbol: String {
        if keyCode == UInt32(kVK_Space) { return L("Space") }
        if let known = ShortcutKeyNames.functionNames[Int(keyCode)] ?? ShortcutKeyNames.specialNames[Int(keyCode)] {
            return known
        }
        return ShortcutKeyNames.character(for: keyCode) ?? L("Key %d", Int(keyCode))
    }

    static let modifierKeyCodes: Set<Int> = Set([
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function
    ])
}

/// Converts hardware key codes to labels while respecting the current keyboard layout.
private enum ShortcutKeyNames {
    static let functionNames: [Int: String] = {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return Dictionary(uniqueKeysWithValues: codes.enumerated().map { ($0.element, "F\($0.offset + 1)") })
    }()
    static let specialNames: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]

    static func character(for code: UInt32) -> String? {
        guard code <= UInt16.max,
              let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKey: UInt32 = 0
        var output = [UniChar](repeating: 0, count: 4)
        var count = 0
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKey, output.count, &count, &output)
        }
        guard status == noErr, count > 0 else { return nil }
        let result = String(utf16CodeUnits: output, count: count).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result.uppercased()
    }
}
