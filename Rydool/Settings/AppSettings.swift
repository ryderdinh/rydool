import AppKit
import Combine

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case copy, save, copyAndSave
    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: L("Copy to Clipboard")
        case .save: L("Save to File")
        case .copyAndSave: L("Copy + Save")
        }
    }

    var buttonTitle: String {
        switch self {
        case .copy: L("Copy")
        case .save: L("Save")
        case .copyAndSave: L("Copy & Save")
        }
    }

    var buttonSymbol: String { self == .save ? "square.and.arrow.down" : "doc.on.doc" }
}

/// The persisted keys are retained for compatibility with existing installations.
private enum PreferenceKey: String {
    case shortcut, historyShortcut, fullScreenShortcut, lastSaveDirectory
    case annotationColor, language
    case lineWeight = "annotationLineWeight"
}

private struct PreferenceStore {
    let defaults: UserDefaults

    static func applicationStore() -> PreferenceStore {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["RYDOOL_TEST_DEFAULTS"],
           environment["RYDOOL_TEST_DATA_DIR"] != nil,
           environment["RYDOOL_TEST_PASTEBOARD"] != nil,
           let defaults = UserDefaults(suiteName: suite) {
            return PreferenceStore(defaults: defaults)
        }
        #endif
        return PreferenceStore(defaults: .standard)
    }

    func shortcut(_ key: PreferenceKey, fallback: ShortcutBinding) -> ShortcutBinding {
        guard let data = defaults.data(forKey: key.rawValue),
              let value = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else { return fallback }
        return value
    }

    func save(_ shortcut: ShortcutBinding, key: PreferenceKey) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key.rawValue)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let store: PreferenceStore

    @Published var shortcut: ShortcutBinding { didSet { store.save(shortcut, key: .shortcut) } }
    @Published var historyShortcut: ShortcutBinding { didSet { store.save(historyShortcut, key: .historyShortcut) } }
    @Published var fullScreenShortcut: ShortcutBinding { didSet { store.save(fullScreenShortcut, key: .fullScreenShortcut) } }
    @Published var language: AppLanguage {
        didSet {
            store.defaults.set(language.rawValue, forKey: PreferenceKey.language.rawValue)
            NotificationCenter.default.post(name: .rydoolLanguageDidChange, object: nil)
        }
    }

    var lastSaveDirectory: URL? {
        get { store.defaults.url(forKey: PreferenceKey.lastSaveDirectory.rawValue) }
        set { store.defaults.set(newValue, forKey: PreferenceKey.lastSaveDirectory.rawValue) }
    }

    var annotationColor: AnnotationColor {
        get { store.defaults.string(forKey: PreferenceKey.annotationColor.rawValue).flatMap(AnnotationColor.init) ?? .red }
        set { store.defaults.set(newValue.rawValue, forKey: PreferenceKey.annotationColor.rawValue) }
    }

    var lineWeight: LineWeight {
        get { LineWeight(rawValue: store.defaults.integer(forKey: PreferenceKey.lineWeight.rawValue)) ?? .medium }
        set { store.defaults.set(newValue.rawValue, forKey: PreferenceKey.lineWeight.rawValue) }
    }

    init(defaults: UserDefaults? = nil) {
        let preferences = defaults.map { PreferenceStore(defaults: $0) } ?? PreferenceStore.applicationStore()
        self.store = preferences
        self.shortcut = preferences.shortcut(.shortcut, fallback: .default)
        self.historyShortcut = preferences.shortcut(.historyShortcut, fallback: .historyDefault)
        self.fullScreenShortcut = preferences.shortcut(.fullScreenShortcut, fallback: .fullScreenDefault)
        self.language = preferences.defaults.string(forKey: PreferenceKey.language.rawValue)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        if preferences.defaults.object(forKey: PreferenceKey.lineWeight.rawValue) == nil {
            preferences.defaults.set(LineWeight.medium.rawValue, forKey: PreferenceKey.lineWeight.rawValue)
        }
    }
}
