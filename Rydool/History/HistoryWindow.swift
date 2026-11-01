import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var pasteTarget: NSRunningApplication?
    private var languageObservation: AnyCancellable?

    func show(target: NSRunningApplication? = nil) {
        if window?.isVisible != true {
            let previous = target ?? NSWorkspace.shared.frontmostApplication
            pasteTarget = previous?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : previous
        }
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            newWindow.title = "Rydool — \(L("Clipboard"))"
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.contentView = NSHostingView(rootView: HistoryView(
                onClose: { [weak self] in self?.window?.close() },
                onCopyAndPaste: { [weak self] in self?.pasteIntoPreviousApp() }
            ))
            window = newWindow
            languageObservation = AppSettings.shared.$language.dropFirst().sink { [weak newWindow] language in
                newWindow?.title = "Rydool — \(Localization.text("Clipboard", language: language))"
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak newWindow] event in
                guard event.window === newWindow, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      event.keyCode == 125 || event.keyCode == 126 else { return event }
                NotificationCenter.default.post(name: .historyMoveSelection, object: Int(event.keyCode))
                return nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyDidOpen, object: nil)
        }
    }

    private func pasteIntoPreviousApp() {
        window?.close()
        guard let target = pasteTarget, !target.isTerminated else { return }
        pasteTarget = nil
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            Alerts.show(title: L("Allow automatic paste"), message: L("The item was copied. To paste automatically, allow Rydool in Privacy & Security → Accessibility, then select the item again. You can also paste with ⌘V."))
            return
        }
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: target) }
        guard target.activate(options: []) else { return }
        postPasteWhenActive(target, attemptsRemaining: 20)
    }

    private func postPasteWhenActive(_ target: NSRunningApplication, attemptsRemaining: Int) {
        guard attemptsRemaining > 0, !target.isTerminated else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard foreground == target.processIdentifier else {
                guard foreground == ProcessInfo.processInfo.processIdentifier || foreground == nil else { return }
                self.postPasteWhenActive(target, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.postToPid(target.processIdentifier)
            up.postToPid(target.processIdentifier)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var history = ClipboardHistory.shared
    @ObservedObject private var languageSettings = AppSettings.shared
    @State private var query = ""
    @State private var selectedID: String?
    @State private var hoveredID: String?
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool
    let onClose: () -> Void
    let onCopyAndPaste: () -> Void

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter { $0.text?.localizedCaseInsensitiveContains(query) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Clipboard")).font(.system(size: 17, weight: .semibold))
                    Text(L("History stored on this Mac")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(L(history.items.count == 1 ? "%d item" : "%d items", history.items.count)).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search history"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { copySelection() }
                if !query.isEmpty { Button(L("Clear search")) { query = "" }.buttonStyle(.borderless) }
            }
            .padding(10).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            if !history.tracking {
                HStack {
                    Text(L("Clipboard tracking is off. Items are saved after you turn it on."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Enable")) { history.tracking = true }
                }
            }
            if let error = history.errorMessage {
                HStack { Text(error).foregroundStyle(.red); Spacer(); Button(L("Close")) { history.errorMessage = nil } }.font(.caption)
            }
            if filtered.isEmpty {
                Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: query.isEmpty ? "clipboard" : "magnifyingglass")
                            .font(.system(size: 24)).foregroundStyle(.tertiary)
                        Text(query.isEmpty ? L("No clipboard history yet") : L("No results found"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(filtered, selection: $selectedID) { item in
                        HStack(spacing: 10) {
                            HStack(spacing: 10) {
                                if item.kind == .image, let image = NSImage(data: item.data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 58, height: 42)
                                        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                                        .frame(width: 58, height: 42)
                                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.text ?? L("Clipboard image")).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                        .font(.system(size: 13, weight: .medium))
                                    TimelineView(.periodic(from: .now, by: 60)) { context in
                                        Text(HistoryRelativeTime.string(since: item.copiedAt, now: context.date))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if history.copy(item) { onCopyAndPaste() } }
                            Button { history.togglePin(item) } label: { Image(systemName: item.isPinned ? "pin.fill" : "pin") }
                                .buttonStyle(.borderless).help(item.isPinned ? L("Unpin") : L("Pin"))
                            Button { history.delete(item) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help(L("Delete"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(hoveredID == item.id ? 0.10 : 0.035))
                        )
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering { hoveredID = item.id }
                            else if hoveredID == item.id { hoveredID = nil }
                        }
                        .tag(item.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: filtered.map(\.id)) { _, ids in
                        if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .historyDidOpen)) { _ in
                        guard let firstID = filtered.first?.id else { return }
                        DispatchQueue.main.async { proxy.scrollTo(firstID, anchor: .top) }
                    }
                }
            }
            HStack {
                Button(L("Clear all…")) { confirmClear = true }.disabled(history.items.isEmpty)
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                Spacer()
                Text(L("↑↓ Select   ↵ Paste")).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(minWidth: 450, minHeight: 350)
        .onReceive(NotificationCenter.default.publisher(for: .historyMoveSelection)) { notification in
            guard !filtered.isEmpty, let key = notification.object as? Int else { return }
            let index = filtered.firstIndex(where: { $0.id == selectedID })
            if key == 125 { selectedID = filtered[min((index ?? -1) + 1, filtered.count - 1)].id }
            if key == 126 { selectedID = filtered[max((index ?? 1) - 1, 0)].id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyDidOpen)) { _ in
            selectedID = nil
            hoveredID = nil
            searchFocused = true
        }
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onClose)
        .alert(L("Clear all history?"), isPresented: $confirmClear) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clear all"), role: .destructive) { history.clear() }
        } message: { Text(L("Pinned items will also be deleted.")) }
    }

    private func copySelection() {
        guard let item = filtered.first(where: { $0.id == selectedID }) ?? filtered.first else { return }
        if history.copy(item) { onCopyAndPaste() }
    }
}

enum HistoryRelativeTime {
    static func string(since date: Date, now: Date = Date(), language: AppLanguage? = nil) -> String {
        let language = language ?? AppSettings.shared.language
        func translate(_ key: String, _ value: Int? = nil) -> String {
            Localization.format(key, language: language, arguments: value.map { [$0] } ?? [])
        }
        let seconds = max(0, now.timeIntervalSince(date))
        guard seconds >= 60 else { return translate("Just now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return translate(minutes == 1 ? "%d minute ago" : "%d minutes ago", minutes) }
        let hours = minutes / 60
        if hours < 24 { return translate(hours == 1 ? "%d hour ago" : "%d hours ago", hours) }
        let days = hours / 24
        if days < 30 { return translate(days == 1 ? "%d day ago" : "%d days ago", days) }
        let months = days / 30
        if months < 12 { return translate(months == 1 ? "%d month ago" : "%d months ago", months) }
        let years = months / 12
        return translate(years == 1 ? "%d year ago" : "%d years ago", years)
    }
}

private extension Notification.Name {
    static let historyMoveSelection = Notification.Name("Rydool.historyMoveSelection")
    static let historyDidOpen = Notification.Name("Rydool.historyDidOpen")
}
