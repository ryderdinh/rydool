import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Intercepts screenshot keys before system shortcuts when Accessibility is granted.
private final class ScreenshotKeyTap {
    static let shared = ScreenshotKeyTap()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var bindings: [UInt32: (ShortcutBinding, () -> Void)] = [:]
    private var consumedKeys: Set<Int64> = []

    func set(_ combo: ShortcutBinding, action: @escaping () -> Void, signature: UInt32) -> Bool {
        guard install() else { return false }
        bindings[signature] = (combo, action)
        return true
    }

    func remove(_ signature: UInt32) { bindings.removeValue(forKey: signature) }

    private func install() -> Bool {
        if let tap, CGEvent.tapIsEnabled(tap: tap) { return true }
        guard AXIsProcessTrusted() else { return false }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return CGEvent.tapIsEnabled(tap: tap) }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ScreenshotKeyTap>.fromOpaque(context).takeUnretainedValue()
            return owner.handle(type, event: event)
        }, userInfo: context) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            consumedKeys.removeAll()
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return consumedKeys.remove(key) != nil ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if consumedKeys.contains(key) { return nil }
        let flags = event.flags
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        guard let (_, action) = bindings.values.first(where: { $0.0.keyCode == key && $0.0.modifierFlags == modifiers }) else {
            return Unmanaged.passUnretained(event)
        }
        consumedKeys.insert(key)
        DispatchQueue.main.async(execute: action)
        return nil
    }
}

/// Routes Carbon hot-key events through a single application event handler.
private final class HotkeyRouter {
    static let shared = HotkeyRouter()
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    func install() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let router = Unmanaged<HotkeyRouter>.fromOpaque(context).takeUnretainedValue()
            guard let action = router.actions[identifier.signature] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async(execute: action)
            return noErr
        }, 1, &eventType, context, &handler)
        guard result == noErr else { throw GlobalHotkeyManager.RegistrationError.failed(result) }
    }

    func setAction(_ action: (() -> Void)?, for signature: UInt32) {
        actions[signature] = action
    }
}

/// Owns one global shortcut; the system consumes the registered key combination.
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager(signature: 0x52594431, interceptScreenshot: true)
    static let history = GlobalHotkeyManager(signature: 0x52594432)
    static let fullScreen = GlobalHotkeyManager(signature: 0x52594433, interceptScreenshot: true)
    static let screenRecording = GlobalHotkeyManager(signature: 0x52594434)

    enum RegistrationError: Error {
        case alreadyInUse
        case failed(OSStatus)
    }

    var onTrigger: (() -> Void)?
    private let signature: UInt32
    private let interceptScreenshot: Bool
    private var registration: EventHotKeyRef?
    private var currentCombo: ShortcutBinding?

    private init(signature: UInt32, interceptScreenshot: Bool = false) {
        self.signature = signature
        self.interceptScreenshot = interceptScreenshot
    }

    func register(_ combo: ShortcutBinding) throws {
        unregister()
        if interceptScreenshot && Self.isSystemScreenshot(combo),
           ScreenshotKeyTap.shared.set(combo, action: { [weak self] in self?.onTrigger?() }, signature: signature) {
            currentCombo = combo
            return
        }
        try HotkeyRouter.shared.install()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: 1)
        let result = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard result == noErr, let reference else {
            if result == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.alreadyInUse }
            throw RegistrationError.failed(result)
        }
        registration = reference
        currentCombo = combo
        HotkeyRouter.shared.setAction({ [weak self] in self?.onTrigger?() }, for: signature)
    }

    func unregister() {
        ScreenshotKeyTap.shared.remove(signature)
        HotkeyRouter.shared.setAction(nil, for: signature)
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        currentCombo = nil
    }

    /// Switch an active fallback registration after Accessibility is granted.
    func promoteToEventTap() {
        guard interceptScreenshot, registration != nil, let combo = currentCombo,
              Self.isSystemScreenshot(combo),
              ScreenshotKeyTap.shared.set(combo, action: { [weak self] in self?.onTrigger?() }, signature: signature) else { return }
        HotkeyRouter.shared.setAction(nil, for: signature)
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }

    static func isSystemScreenshot(_ combo: ShortcutBinding) -> Bool {
        let key = combo.keyCode
        let flags = combo.modifierFlags
        return [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(key)
            && (flags == [.command, .shift] || (key != UInt32(kVK_ANSI_5) && flags == [.command, .shift, .control]))
    }

}
