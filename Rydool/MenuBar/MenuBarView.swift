import SwiftUI

/// A command and its presentation in the status menu.
private struct MenuCommand: Identifiable {
    enum Identifier: Hashable {
        case captureArea, captureScreen, record, recent, permission, history, tracking, settings, quit
    }
    enum Trailing {
        case none, shortcut(String), detail(String)
    }
    let id: Identifier
    let symbol: String
    let title: String
    var trailing: Trailing = .none
    var warning = false
    var subtle = false
    let action: () -> Void
}

struct MenuBarView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var permission: PermissionStatus
    @ObservedObject var history = ClipboardHistory.shared
    @ObservedObject var previews = ScreenshotPreviews.shared
    @ObservedObject var recording = RecordingCoordinator.shared
    let onHistory: () -> Void
    let onFullScreen: () -> Void
    let onCapture: () -> Void
    let onRecording: () -> Void
    let onRecentScreenshots: () -> Void
    let onGrantPermission: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            section(L("SCREENSHOT"), commands: screenshotCommands)
            section(L("CLIPBOARD"), commands: clipboardCommands).padding(.top, 8)
            Divider().padding(.horizontal, 16).padding(.vertical, 9)
            MenuCommandRow(command: settingsCommand)
            MenuCommandRow(command: quitCommand).keyboardShortcut("q", modifiers: .command)
        }
        .padding(.bottom, 9)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Rydool").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(recording.phase == .recording ? Color.red : history.tracking ? Color.green : Color.secondary).frame(width: 6, height: 6)
                    if recording.phase == .recording, let start = recording.startedAt {
                        Text(L("Recording…")) + Text(" ") + Text(start, style: .timer)
                    } else {
                        Text(history.tracking ? L("History on") : L("History paused"))
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 12)
    }

    private func section(_ title: String, commands: [MenuCommand]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 4)
            ForEach(commands) { MenuCommandRow(command: $0) }
        }
    }

    private var screenshotCommands: [MenuCommand] {
        var commands = [
            MenuCommand(id: .captureArea, symbol: "viewfinder", title: L("Capture Area"),
                        trailing: .shortcut(settings.shortcut.displayString), action: onCapture),
            MenuCommand(id: .captureScreen, symbol: "rectangle.dashed", title: L("Capture Full Screen"),
                        trailing: .shortcut(settings.fullScreenShortcut.displayString), action: onFullScreen)
        ]
        let recordingTitle: String
        switch recording.phase {
        case .idle: recordingTitle = L("Record Screen")
        case .preparing: recordingTitle = L("Preparing recording…")
        case .recording: recordingTitle = L("Stop recording")
        case .finishing: recordingTitle = L("Finishing recording…")
        case .pendingSave: recordingTitle = L("Save recording…")
        }
        commands.append(MenuCommand(id: .record, symbol: recording.phase == .recording ? "stop.circle.fill" : "record.circle",
                                    title: recordingTitle, trailing: .shortcut(settings.recordingShortcut.displayString), warning: recording.phase == .recording, action: onRecording))
        if previews.hiddenCount > 0 {
            commands.append(MenuCommand(id: .recent, symbol: "photo.stack", title: L("Recent Screenshots"),
                                        trailing: .detail("\(previews.hiddenCount)"), action: onRecentScreenshots))
        }
        if !permission.isGranted {
            commands.append(MenuCommand(id: .permission, symbol: "exclamationmark.triangle",
                                        title: L("Allow Screen Recording…"), warning: true, action: onGrantPermission))
        }
        return commands
    }

    private var clipboardCommands: [MenuCommand] {
        [MenuCommand(id: .history, symbol: "clipboard", title: L("Clipboard History"),
                     trailing: .shortcut(settings.historyShortcut.displayString), action: onHistory),
         MenuCommand(id: .tracking, symbol: history.tracking ? "pause.circle" : "play.circle",
                     title: history.tracking ? L("Pause Clipboard History") : L("Enable Clipboard History"),
                     action: { history.tracking.toggle() })]
    }

    private var settingsCommand: MenuCommand {
        MenuCommand(id: .settings, symbol: "gearshape", title: L("Settings…"), subtle: true, action: onSettings)
    }
    private var quitCommand: MenuCommand {
        MenuCommand(id: .quit, symbol: "power", title: L("Quit Rydool"), trailing: .shortcut("⌘Q"), subtle: true, action: onQuit)
    }
}

private struct MenuCommandRow: View {
    let command: MenuCommand
    @State private var hovering = false

    var body: some View {
        Button(action: command.action) {
            HStack(spacing: 10) {
                Image(systemName: command.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(command.warning ? Color.orange : command.subtle ? Color.secondary : Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background((command.warning ? Color.orange : Color.accentColor).opacity(command.subtle ? 0 : 0.10),
                                in: RoundedRectangle(cornerRadius: 7))
                Text(command.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8).frame(height: 38).frame(maxWidth: .infinity, alignment: .leading)
            .background { hoverSurface }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(command.title)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var hoverSurface: some View {
        if hovering {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 8).fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch command.trailing {
        case .none:
            EmptyView()
        case .shortcut(let value):
            Text(value).font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
        case .detail(let value):
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}
