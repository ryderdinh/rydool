import AppKit
import UniformTypeIdentifiers

enum ImageExportFailure: LocalizedError {
    case encodingFailed
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            L("Rydool couldn't prepare the image. Please try again.")
        case .writeFailed(let url):
            L("Rydool couldn't save to “%@”. Check that the folder exists and you can write to it.", url.deletingLastPathComponent().lastPathComponent)
        }
    }
}

/// File operations are independent of the save panel and can use a temporary directory.
struct ScreenshotFileStore {
    private let files = FileManager.default

    func save(_ screenshot: RenderedScreenshot, to destination: URL) throws {
        guard let png = screenshot.pngData() else { throw ImageExportFailure.encodingFailed }
        do { try png.write(to: destination, options: .atomic) }
        catch { throw ImageExportFailure.writeFailed(destination) }
    }

    func availableURL(in directory: URL, named filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        var suffix = 1
        while true {
            let candidateName = suffix == 1 ? filename : "\(name) (\(suffix)).png"
            let candidate = directory.appendingPathComponent(candidateName)
            if !files.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}

enum ScreenshotExport {
    enum PanelResult {
        case saved(URL)
        case cancelled
        case failed(Error)
    }

    static var defaultDirectory: URL {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let path = env["RYDOOL_TEST_DATA_DIR"], env["RYDOOL_TEST_PASTEBOARD"] != nil,
           env["RYDOOL_TEST_DEFAULTS"] != nil {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        if let previous = AppSettings.shared.lastSaveDirectory { return previous }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func defaultFileName(date: Date = Date()) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Rydool \(clock.string(from: date)).png"
    }

    static func saveToDefaultLocation(_ screenshot: RenderedScreenshot) throws -> URL {
        let store = ScreenshotFileStore()
        let destination = store.availableURL(in: defaultDirectory, named: defaultFileName())
        try store.save(screenshot, to: destination)
        return destination
    }

    static func presentSavePanel(_ screenshot: RenderedScreenshot) -> PanelResult {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = defaultDirectory
        panel.nameFieldStringValue = defaultFileName()
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return .cancelled }
        do {
            try ScreenshotFileStore().save(screenshot, to: destination)
            AppSettings.shared.lastSaveDirectory = destination.deletingLastPathComponent()
            return .saved(destination)
        } catch {
            return .failed(error)
        }
    }
}
