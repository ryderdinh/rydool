import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class SettingsNavigation: ObservableObject {
    @Published var section: SettingsSection = .general
}

/// Preferences displayed in the settings window.
struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var launchAtLogin = LaunchAtLogin.shared
    @ObservedObject var recorder: ShortcutCaptureController
    @ObservedObject var history = ClipboardHistory.shared
    @ObservedObject var historyRecorder: ShortcutCaptureController
    @ObservedObject var fullScreenRecorder: ShortcutCaptureController
    @ObservedObject var screenRecordingRecorder: ShortcutCaptureController
    @ObservedObject var navigation: SettingsNavigation
    @State private var excludedApplicationError: String?
    @State private var screenGranted = ScreenAccess.isGranted
    @State private var accessibilityGranted = AccessibilityAccess.isGranted
    @State private var microphoneGranted = MicrophoneAccess.isGranted
    @State private var resettingPermission = false
    @State private var permissionResetFailed = false
    private let permissionRefresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var section: SettingsSection { navigation.section }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    switch section {
                    case .general: generalSettings
                    case .recording: recordingSettings
                    case .shortcuts: shortcutSettings
                    case .clipboard: clipboardSettings
                    case .permissions: permissionSettings
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
            screenRecordingRecorder.cancel()
        }
        .onReceive(permissionRefresh) { _ in
            guard section == .permissions else { return }
            screenGranted = ScreenAccess.isGranted
            accessibilityGranted = AccessibilityAccess.isGranted
            microphoneGranted = MicrophoneAccess.isGranted
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
                    Button { navigation.section = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                            Text(item.title).font(.system(size: 13, weight: section == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(section == item ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background { selectionSurface(isSelected: section == item) }
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
        .background { sidebarSurface }
    }

    @ViewBuilder private var sidebarSurface: some View {
        if #available(macOS 26.0, *) {
            Rectangle().fill(.regularMaterial)
        } else {
            Color.primary.opacity(0.035)
        }
    }

    @ViewBuilder private func selectionSurface(isSelected: Bool) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08))
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.12)), in: .rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.13))
            }
        }
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

    private var recordingSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("VIDEO QUALITY"))
                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "rectangle.on.rectangle", color: .blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Resolution")).fontWeight(.medium)
                            Text(L("Never enlarges the selected area"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Picker(L("Resolution"), selection: $settings.recordingResolution) {
                            ForEach(RecordingResolution.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 130)
                    }
                    Divider()
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "film", color: .blue)
                        Text(L("Frame rate")).fontWeight(.medium)
                        Spacer(minLength: 8)
                        Picker(L("Frame rate"), selection: $settings.recordingFrameRate) {
                            ForEach(RecordingFrameRate.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                    }
                    Divider()
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "slider.horizontal.3", color: .blue)
                        Text(L("Quality")).fontWeight(.medium)
                        Spacer(minLength: 8)
                        Picker(L("Quality"), selection: $settings.recordingBitrate) {
                            ForEach(RecordingBitrate.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 150)
                    }
                }
                Text(L("Higher quality and frame rates may create larger files."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(L("AUDIO"))
                SettingsCard {
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "speaker.wave.2", color: .blue)
                        Toggle(L("System audio"), isOn: $settings.recordingSystemAudio)
                            .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L("System audio"))
                    }
                    Divider()
                    HStack(spacing: 12) {
                        SettingsSymbol(symbol: "mic", color: .blue)
                        Toggle(L("Microphone"), isOn: $settings.recordingMicrophone)
                            .toggleStyle(.switch).controlSize(.small).accessibilityLabel(L("Microphone"))
                    }
                }
                Text(L("These choices are also available before each recording."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                ShortcutSetting(title: L("Record Screen"), symbol: "record.circle", recorder: screenRecordingRecorder, shortcut: settings.recordingShortcut)
                Divider()
                ShortcutSetting(title: L("Clipboard History"), symbol: "clipboard", recorder: historyRecorder, shortcut: settings.historyShortcut)
            }
            Text(L("If a shortcut conflicts with another app or macOS, choose a different combination."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: screenGranted && accessibilityGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(screenGranted && accessibilityGranted ? L("You're all set") : L("Make Rydool work for you"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L("Choose what to allow in macOS. You can change this anytime."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            permissionRow(symbol: "viewfinder", color: .blue, title: L("Screen Recording"),
                          description: L("Capture your screen and edit screenshots."),
                          granted: screenGranted, service: .screenRecording, action: ScreenAccess.openSystemSettings)
            permissionRow(symbol: "keyboard", color: .purple, title: L("Accessibility"),
                          description: L("Use screenshot shortcuts and paste clipboard items into other apps."),
                          granted: accessibilityGranted, service: .accessibility, action: AccessibilityAccess.openSystemSettings)
            permissionRow(symbol: "mic", color: .orange, title: L("Microphone"),
                          description: L("Optionally include your voice in screen recordings."),
                          granted: microphoneGranted, service: .microphone, action: MicrophoneAccess.openSystemSettings)
            if permissionResetFailed {
                Text(L("Couldn't reset this permission. Remove Rydool from the corresponding list in System Settings, then add it again."))
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(L("After allowing Screen Recording, macOS may ask you to reopen Rydool."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(L("Reopen Rydool"), action: ScreenAccess.relaunch).buttonStyle(.link)
            }
            .font(.caption)
            .padding(.top, 2)
        }
    }

    private func permissionRow(symbol: String, color: Color, title: String, description: String,
                               granted: Bool, service: PermissionReset.Service, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(title).fontWeight(.semibold)
                    Label(granted ? L("Allowed") : L("Not allowed"), systemImage: granted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(granted ? Color.green : Color.secondary)
                }
                Text(description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button(granted ? L("Manage…") : L("Open Settings…"), action: action)
                    .controlSize(.small)
                Button(L("Reset permission")) { resetPermission(service, then: action) }
                    .buttonStyle(.link).font(.caption)
                    .disabled(resettingPermission)
                    .help(L("Remove Rydool's saved permission and ask macOS again."))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func resetPermission(_ service: PermissionReset.Service, then request: @escaping () -> Void) {
        resettingPermission = true
        permissionResetFailed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let succeeded = (try? PermissionReset.reset(service)) != nil
            DispatchQueue.main.async {
                resettingPermission = false
                if succeeded { request() } else { permissionResetFailed = true }
            }
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

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, recording, shortcuts, clipboard, permissions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L("General")
        case .recording: L("Recording")
        case .shortcuts: L("Shortcuts")
        case .clipboard: L("Clipboard")
        case .permissions: L("Permissions")
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .recording: "record.circle"
        case .shortcuts: "keyboard"
        case .clipboard: "clipboard"
        case .permissions: "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: L("Customize how Rydool works on your Mac.")
        case .recording: L("Choose the default quality and audio for screen recordings.")
        case .shortcuts: L("Choose shortcuts for quick access to your tools.")
        case .clipboard: L("Manage clipboard history and excluded apps.")
        case .permissions: L("Give Rydool access to the features you want to use.")
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
