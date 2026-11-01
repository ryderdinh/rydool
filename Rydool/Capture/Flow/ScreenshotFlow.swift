import AppKit
import ImageIO

/// Mutable state belonging to one capture attempt, including its temporary windows.
@MainActor
private final class CaptureSession {
    let sourceApp: NSRunningApplication?
    var windows: [SelectionWindow] = []
    var overlays: [SelectionCanvas] = []
    var screenObserver: NSObjectProtocol?

    init(sourceApp: NSRunningApplication?) { self.sourceApp = sourceApp }
}

/// Connects screen capture, selection, previews, and editor windows.
@MainActor
final class ScreenshotFlow {
    static let shared = ScreenshotFlow()
    var willBeginCapture: (() -> Void)?
    private var session: CaptureSession?
    private var editors: [UUID: ScreenshotEditor] = [:]
    var isCapturing: Bool { session != nil }
    private init() {}

    func start(fullScreen: Bool = false) {
        guard session == nil else { return }
        let synthetic = Self.syntheticCaptureURL()
        guard synthetic != nil || ScreenAccess.isGranted else {
            PermissionWindowController.shared.show()
            return
        }

        willBeginCapture?()
        HUD.dismiss()
        ScreenshotPreviews.shared.hideAll()
        let front = NSWorkspace.shared.frontmostApplication
        let source = front == .current ? nil : front
        let active = CaptureSession(sourceApp: source)
        session = active

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let images = try await self.snapshotDisplays(synthetic: synthetic)
                guard self.session === active else { return }
                self.present(images, fullScreen: fullScreen, session: active)
            } catch {
                guard self.session === active else { return }
                self.closeSession(restoreFocus: false)
                if case SnapshotFailure.permissionDenied = error {
                    PermissionWindowController.shared.show()
                } else {
                    Alerts.show(error)
                }
            }
        }
    }

    func cancel() { closeSession(restoreFocus: true) }

    func allowSelection(_ overlay: SelectionCanvas) -> Bool {
        guard let session else { return false }
        let otherOverlays = session.overlays.filter { $0 !== overlay }
        guard !otherOverlays.contains(where: \.hasAnnotations) else { return false }
        otherOverlays.forEach { if $0.hasSelection { $0.clearSelection() } }
        return true
    }

    func completeSelection(from overlay: SelectionCanvas) {
        guard let image = overlay.renderScreenshot(),
              let window = overlay.window as? SelectionWindow else { return }
        finishCapture(image, screen: window.screen ?? NSScreen.main)
    }

    func finish(_ output: CaptureOutput, from overlay: SelectionCanvas) {
        guard let screenshot = overlay.renderScreenshot() else {
            Alerts.show(title: L("Couldn't export image"), message: L("Select the capture area and try again."))
            return
        }
        if output == .saveAs {
            showSavePanel(screenshot)
            return
        }
        do {
            try ScreenshotClipboard.copy(screenshot, source: session?.sourceApp?.bundleIdentifier)
            guard let window = overlay.window as? SelectionWindow else { return }
            showPreview(screenshot, screen: window.screen ?? NSScreen.main)
        } catch { Alerts.show(error) }
    }

    private static func syntheticCaptureURL() -> URL? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["RYDOOL_TEST_DATA_DIR"] != nil, env["RYDOOL_TEST_PASTEBOARD"] != nil,
              env["RYDOOL_TEST_DEFAULTS"] != nil, let path = env["RYDOOL_TEST_CAPTURE_IMAGE"] else { return nil }
        return URL(fileURLWithPath: path)
        #else
        return nil
        #endif
    }

    private func snapshotDisplays(synthetic: URL?) async throws -> [DisplaySnapshot] {
        #if DEBUG
        if let synthetic {
            guard let source = CGImageSourceCreateWithURL(synthetic as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
                throw SnapshotFailure.noDisplays
            }
            return [DisplaySnapshot(screen: screen, image: image)]
        }
        #endif
        return try await DisplaySnapshotService.shared.captureDisplays()
    }

    private func present(_ screenshots: [DisplaySnapshot], fullScreen: Bool, session: CaptureSession) {
        let pointer = NSEvent.mouseLocation
        if fullScreen, let screenshot = screenshots.first(where: { $0.screen.frame.contains(pointer) }) ?? screenshots.first {
            let image = RenderedScreenshot(image: screenshot.image, pointSize: screenshot.screen.frame.size)
            finishCapture(image, screen: screenshot.screen)
            return
        }
        let tools = MarkupSession()
        var preferred: SelectionWindow?
        for screenshot in screenshots {
            let window = SelectionWindow(screen: screenshot.screen)
            let view = SelectionCanvas(frame: CGRect(origin: .zero, size: screenshot.screen.frame.size),
                                          image: screenshot.image, toolState: tools)
            view.coordinator = self
            window.contentView = view
            window.initialFirstResponder = view
            session.windows.append(window)
            session.overlays.append(view)
            if screenshot.screen.frame.contains(pointer) { preferred = window }
        }
        NSApp.activate(ignoringOtherApps: true)
        session.windows.filter { $0 !== preferred }.forEach { $0.orderFrontRegardless() }
        let focused = preferred ?? session.windows.first
        focused?.makeKeyAndOrderFront(nil)
        if let view = focused?.contentView { focused?.makeFirstResponder(view) }
        NSCursor.crosshair.set()
        session.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
    }

    private func finishCapture(_ screenshot: RenderedScreenshot, screen: NSScreen?) {
        var error: Error?
        do { try ScreenshotClipboard.copy(screenshot, source: session?.sourceApp?.bundleIdentifier) }
        catch let failure { error = failure }
        showPreview(screenshot, screen: screen)
        if let error { Alerts.show(error) }
    }

    private func showPreview(_ screenshot: RenderedScreenshot, screen: NSScreen?) {
        let sourceApp = session?.sourceApp
        closeSession(restoreFocus: true)
        addPreview(screenshot, sourceApp: sourceApp, screen: screen)
    }

    private func addPreview(_ screenshot: RenderedScreenshot, sourceApp: NSRunningApplication?, screen: NSScreen?) {
        ScreenshotPreviews.shared.add(screenshot, source: sourceApp?.bundleIdentifier, screen: screen) { [weak self] id in
            guard let self, !self.isCapturing else { return }
            ScreenshotPreviews.shared.remove(id)
            let editor = ScreenshotEditor(screenshot: screenshot, screen: screen,
                onFinish: { [weak self] image, output in
                    self?.finishEditor(id, image: image, output: output, sourceApp: sourceApp, screen: screen)
                }, onCancel: { [weak self] in
                    self?.closeEditor(id, sourceApp: sourceApp)
                    self?.addPreview(screenshot, sourceApp: sourceApp, screen: screen)
                })
            self.editors[id] = editor
            editor.show()
        }
    }

    private func finishEditor(_ id: UUID, image: RenderedScreenshot, output: CaptureOutput,
                              sourceApp: NSRunningApplication?, screen: NSScreen?) {
        if output == .saveAs {
            editors[id]?.hide()
            switch ScreenshotExport.presentSavePanel(image) {
            case .saved:
                closeEditor(id, sourceApp: sourceApp)
                addPreview(image, sourceApp: sourceApp, screen: screen)
            case .cancelled:
                editors[id]?.show()
            case .failed(let error):
                editors[id]?.show()
                Alerts.show(error)
            }
            return
        }
        do {
            try ScreenshotClipboard.copy(image, source: sourceApp?.bundleIdentifier)
            closeEditor(id, sourceApp: sourceApp)
            addPreview(image, sourceApp: sourceApp, screen: screen)
        } catch { Alerts.show(error) }
    }

    private func closeEditor(_ id: UUID, sourceApp: NSRunningApplication?) {
        editors.removeValue(forKey: id)?.close()
        if let sourceApp, !sourceApp.isTerminated { sourceApp.activate() }
    }

    private func showSavePanel(_ screenshot: RenderedScreenshot) {
        guard let session else { return }
        session.windows.forEach { $0.orderOut(nil) }
        switch ScreenshotExport.presentSavePanel(screenshot) {
        case .saved:
            if let overlay = session.overlays.first(where: \.hasSelection),
               let window = overlay.window as? SelectionWindow {
                showPreview(screenshot, screen: window.screen ?? NSScreen.main)
            } else { closeSession(restoreFocus: true) }
        case .cancelled:
            restoreSelectionWindows(session)
        case .failed(let error):
            restoreSelectionWindows(session)
            Alerts.show(error)
        }
    }

    private func restoreSelectionWindows(_ session: CaptureSession) {
        session.windows.forEach { $0.orderFrontRegardless() }
        session.windows.first(where: { ($0.contentView as? SelectionCanvas)?.hasSelection == true })?.makeKey()
    }

    private func closeSession(restoreFocus: Bool) {
        guard let active = session else { return }
        session = nil
        if let observer = active.screenObserver { NotificationCenter.default.removeObserver(observer) }
        active.windows.forEach { $0.orderOut(nil) }
        active.windows.removeAll()
        active.overlays.removeAll()
        NSCursor.arrow.set()
        ScreenshotPreviews.shared.showAll()
        if restoreFocus, let sourceApp = active.sourceApp, !sourceApp.isTerminated { sourceApp.activate() }
    }
}
