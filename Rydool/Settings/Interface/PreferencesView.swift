import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Preferences displayed in the settings window.
struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var launchAtLogin = LaunchAtLogin.shared
    @ObservedObject var recorder: ShortcutCaptureController
    @ObservedObject var history = ClipboardHistory.shared
    @ObservedObject var historyRecorder: ShortcutCaptureController
    @ObservedObject var fullScreenRecorder: ShortcutCaptureController
    @State private var excludedApplicationError: String?
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    switch section {
                    case .general: generalSettings
                    case .shortcuts: shortcutSettings
                    case .clipboard: clipboardSettings
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 420)
        .onChange(of: section) { _, _ in
            recorder.cancel()
            historyRecorder.cancel()
            fullScreenRecorder.cancel()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rydool").font(.system(size: 14, weight: .semibold))
                    Text(L("Settings")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 24)
            .padding(.bottom, 25)

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                            Text(item.title).font(.system(size: 13, weight: section == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(section == item ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(section == item ? Color.accentColor.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 10)
        }
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.system(size: 23, weight: .bold))
            Text(section.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("LANGUAGE"))
                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "globe", color: .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Language")).fontWeight(.medium)
                            Text(L("Choose the language used by Rydool."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Picker(L("Language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("STARTUP"))
                SettingsCard {
                    HStack(alignment: .center, spacing: 12) {
                        SettingsSymbol(symbol: "power", color: .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Launch Rydool at login")).fontWeight(.medium)
                            Text(L("Keep Rydool ready in the menu bar when you sign in."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle(L("Launch Rydool at login"), isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    if launchAtLogin.needsApproval {
                        Button(L("Allow Rydool in Login Items…")) { launchAtLogin.openLoginItemsSettings() }
                            .buttonStyle(.link).font(.caption)
                    } else if let error = launchAtLogin.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading(L("GLOBAL SHORTCUTS"))
            SettingsCard {
                ShortcutSetting(title: L("Capture Area"), symbol: "viewfinder", recorder: recorder, shortcut: settings.shortcut)
                Divider()
                ShortcutSetting(title: L("Capture Full Screen"), symbol: "rectangle.dashed", recorder: fullScreenRecorder, shortcut: settings.fullScreenShortcut)
                Divider()
                ShortcutSetting(title: L("Clipboard History"), symbol: "clipboard", recorder: historyRecorder, shortcut: settings.historyShortcut)
            }
            Text(L("If a shortcut conflicts with another app or macOS, choose a different combination."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var clipboardSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("HISTORY"))
                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "clipboard", color: .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Save clipboard history")).fontWeight(.medium)
                            Text(L("Save copied items on this Mac."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle(L("Save clipboard history"), isOn: $history.tracking)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Divider()
                    HStack {
                        Text(L("Unpinned items: %d", history.maxItems))
                        Spacer()
                        Stepper(L("Unpinned items"), value: $history.maxItems, in: 1...5000, step: 50).labelsHidden()
                    }
                    HStack {
                        Text(L("Maximum storage: %d MB", history.maxMegabytes))
                        Spacer()
                        Stepper(L("Maximum storage"), value: $history.maxMegabytes, in: 20...5000, step: 20).labelsHidden()
                    }
                }
                Text(L("History may contain sensitive information. Rydool cannot detect every password."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("EXCLUDED APPS"))
                SettingsCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Exclude applications")).fontWeight(.medium)
                        Text(L("Copied content from these apps won't be added to history. The source app is an estimate."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if history.excludedApplicationIDs.isEmpty {
                        Text(L("No applications selected")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Divider()
                        ForEach(history.excludedApplicationIDs, id: \.self) { id in
                            ExcludedApplicationRow(id: id, history: history)
                        }
                    }
                    Button { chooseExcludedApplications() } label: {
                        Label(L("Add application…"), systemImage: "plus")
                    }
                    .controlSize(.small)
                    if let excludedApplicationError {
                        Text(excludedApplicationError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }

    private func chooseExcludedApplications() {
        let panel = NSOpenPanel()
        panel.message = L("Choose applications to exclude from clipboard history.")
        panel.prompt = L("Add")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        let invalid = history.addExcludedApplications(panel.urls)
        excludedApplicationError = invalid == 0 ? nil : L("Couldn't identify one or more selected applications.")
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcuts, clipboard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L("General")
        case .shortcuts: L("Shortcuts")
        case .clipboard: L("Clipboard")
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .shortcuts: "keyboard"
        case .clipboard: "clipboard"
        }
    }
    var subtitle: String {
        switch self {
        case .general: L("Customize how Rydool works on your Mac.")
        case .shortcuts: L("Choose shortcuts for quick access to your tools.")
        case .clipboard: L("Manage clipboard history and excluded apps.")
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct SettingsSymbol: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ExcludedApplicationRow: View {
    let id: String
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        let url = history.excludedApplicationURL(id)
        let bundle = url.flatMap(Bundle.init(url:))
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url?.deletingPathExtension().lastPathComponent
            ?? history.excludedApplicationLastKnownName(id)
            ?? L("Unknown application")
        return HStack(spacing: 7) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if url == nil {
                    Text(history.excludedApplicationLastKnownName(id) == nil ? id : L("Application not found"))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button { history.removeExcludedApplication(id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("Remove %@ from list", name))
                .help(L("Remove %@ from list", name))
        }
        .font(.caption)
    }
}

private struct ShortcutSetting: View {
    let title: String
    let symbol: String
    @ObservedObject var recorder: ShortcutCaptureController
    let shortcut: ShortcutBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsSymbol(symbol: symbol, color: .blue)
                Text(title).fontWeight(.medium)
                Spacer()
                ShortcutCaptureIndicator(recorder: recorder, shortcut: shortcut)
            }
            controls
            if let message = recorder.message {
                ShortcutMessage(message: message)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Spacer()
            if !recorder.isRecording && shortcut != recorder.defaultCombo {
                Button(L("Reset"), action: recorder.resetToDefault).buttonStyle(.link)
            }
            Button(recorder.isRecording ? L("Cancel") : L("Change shortcut")) {
                if recorder.isRecording { recorder.cancel() } else { recorder.start() }
            }
            .buttonStyle(.link)
        }
        .font(.system(size: 12))
    }
}

private struct ShortcutCaptureIndicator: View {
    @ObservedObject var recorder: ShortcutCaptureController
    let shortcut: ShortcutBinding

    @ViewBuilder var body: some View {
        if recorder.isRecording && recorder.liveModifiers.isEmpty {
            Text(L("Press a shortcut…")).font(.caption).foregroundStyle(Color.accentColor)
        } else {
            let keys = recorder.isRecording ? ShortcutBinding.modifierSymbols(recorder.liveModifiers) : shortcut.keyCaps
            ShortcutKeyCaps(keys: keys, highlighted: recorder.isRecording)
        }
    }
}

private struct ShortcutMessage: View {
    let message: ShortcutCaptureController.Message
    var body: some View {
        let isError = message.kind == .error
        Label(message.text, systemImage: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(isError ? Color.red : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutKeyCaps: View {
    let keys: [String]
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys.indices, id: \.self) { index in
                KeyCap(label: keys[index], highlighted: highlighted)
            }
        }
    }
}

private struct KeyCap: View {
    let label: String
    let highlighted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, label.count > 1 ? 4 : 0)
            .background(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}
