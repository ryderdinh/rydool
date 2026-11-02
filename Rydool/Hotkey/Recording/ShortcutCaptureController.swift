import AppKit
import Carbon.HIToolbox

/// Dependencies of shortcut recording, separated from the key-event lifecycle.
protocol ShortcutRecordingEnvironment: AnyObject {
    func current(for action: ShortcutCaptureController.Action) -> ShortcutBinding
    func save(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action)
    func register(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action) throws
    func unregister(_ action: ShortcutCaptureController.Action)
    func validate(_ combo: ShortcutBinding) -> ShortcutValidation
}

private final class SystemShortcutEnvironment: ShortcutRecordingEnvironment {
    static let shared = SystemShortcutEnvironment()
    private let settings = AppSettings.shared

    private func manager(_ action: ShortcutCaptureController.Action) -> GlobalHotkeyManager {
        switch action {
        case .region: .shared
        case .history: .history
        case .fullScreen: .fullScreen
        case .screenRecording: .screenRecording
        }
    }

    func current(for action: ShortcutCaptureController.Action) -> ShortcutBinding {
        switch action {
        case .region: settings.shortcut
        case .history: settings.historyShortcut
        case .fullScreen: settings.fullScreenShortcut
        case .screenRecording: settings.recordingShortcut
        }
    }

    func save(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action) {
        switch action {
        case .region: settings.shortcut = combo
        case .history: settings.historyShortcut = combo
        case .fullScreen: settings.fullScreenShortcut = combo
        case .screenRecording: settings.recordingShortcut = combo
        }
    }

    func register(_ combo: ShortcutBinding, for action: ShortcutCaptureController.Action) throws {
        try manager(action).register(combo)
    }

    func unregister(_ action: ShortcutCaptureController.Action) { manager(action).unregister() }
    func validate(_ combo: ShortcutBinding) -> ShortcutValidation { ShortcutValidator.validate(combo) }
}

/// Temporarily suspends global shortcuts while the user records a replacement.
final class ShortcutCaptureController: ObservableObject {
    struct Message: Equatable {
        enum Kind { case error, warning, info }
        let text: String
        let kind: Kind
    }
    enum Action: CaseIterable, Hashable { case region, history, fullScreen, screenRecording }

    @Published private(set) var isRecording = false
    @Published private(set) var liveModifiers: NSEvent.ModifierFlags = []
    @Published var message: Message?
    let action: Action
    private let environment: any ShortcutRecordingEnvironment
    private var monitor: Any?
    private static weak var activeRecorder: ShortcutCaptureController?

    convenience init(_ action: Action = .region) {
        self.init(action, environment: SystemShortcutEnvironment.shared)
    }

    init(_ action: Action, environment: any ShortcutRecordingEnvironment) {
        self.action = action
        self.environment = environment
    }

    var current: ShortcutBinding { environment.current(for: action) }
    var defaultCombo: ShortcutBinding {
        switch action {
        case .region: .default
        case .history: .historyDefault
        case .fullScreen: .fullScreenDefault
        case .screenRecording: .recordingDefault
        }
    }

    func start() {
        guard !isRecording else { return }
        Self.activeRecorder?.cancel()
        Self.activeRecorder = self
        message = nil
        liveModifiers = []
        isRecording = true
        Action.allCases.forEach { environment.unregister($0) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    func cancel() {
        guard isRecording else { return }
        let otherFailure = finishRecording()
        restoreCurrentShortcut()
        if let otherFailure { message = otherFailure }
    }

    func resetToDefault() {
        cancel()
        apply(defaultCombo)
    }

    private func finishRecording() -> Message? {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let hadMonitor = isRecording
        isRecording = false
        liveModifiers = []
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        guard hadMonitor else { return nil }
        let failures = Action.allCases.filter { $0 != action }.compactMap { other -> String? in
            let combo = environment.current(for: other)
            do { try environment.register(combo, for: other); return nil }
            catch { return combo.displayString }
        }
        if failures.isEmpty { return nil }
        return Message(text: L("Couldn't restore shortcut %@. Set it again in Settings.", failures.joined(separator: ", ")), kind: .error)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(ShortcutBinding.supportedModifiers)
        if event.type == .flagsChanged { liveModifiers = flags; return }
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty { cancel(); return }
        apply(ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: flags))
    }

    func apply(_ combo: ShortcutBinding) {
        let validation = environment.validate(combo)
        if case .invalid(let reason) = validation {
            message = Message(text: reason, kind: .error)
            return
        }
        let used = Action.allCases.filter { $0 != action }.map { environment.current(for: $0) }
        guard !used.contains(combo) else {
            message = Message(text: L("This shortcut is already used by another Rydool feature."), kind: .error)
            return
        }
        do {
            try environment.register(combo, for: action)
        } catch {
            message = Message(text: L("Another app is already using %@. Try a different shortcut.", combo.displayString), kind: .error)
            if !isRecording { restoreCurrentShortcut() }
            return
        }
        let otherFailure = finishRecording()
        environment.save(combo, for: action)
        if let otherFailure { message = otherFailure }
        else if case .warning(let warning) = validation { message = Message(text: warning, kind: .warning) }
        else { message = nil }
    }

    private func restoreCurrentShortcut() {
        do { try environment.register(current, for: action) }
        catch { message = Message(text: L("%@ is in use by another app. Choose a different shortcut.", current.displayString), kind: .error) }
    }
}
