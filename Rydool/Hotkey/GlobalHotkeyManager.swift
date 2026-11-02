import AppKit
import Carbon.HIToolbox

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
    static let shared = GlobalHotkeyManager(signature: 0x52594431)
    static let history = GlobalHotkeyManager(signature: 0x52594432)
    static let fullScreen = GlobalHotkeyManager(signature: 0x52594433)
    static let screenRecording = GlobalHotkeyManager(signature: 0x52594434)

    enum RegistrationError: Error {
        case alreadyInUse
        case failed(OSStatus)
    }

    var onTrigger: (() -> Void)?
    private let signature: UInt32
    private var registration: EventHotKeyRef?

    private init(signature: UInt32) { self.signature = signature }

    func register(_ combo: ShortcutBinding) throws {
        try HotkeyRouter.shared.install()
        unregister()
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: signature, id: 1)
        let result = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard result == noErr, let reference else {
            if result == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.alreadyInUse }
            throw RegistrationError.failed(result)
        }
        registration = reference
        HotkeyRouter.shared.setAction({ [weak self] in self?.onTrigger?() }, for: signature)
    }

    func unregister() {
        HotkeyRouter.shared.setAction(nil, for: signature)
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }
}
