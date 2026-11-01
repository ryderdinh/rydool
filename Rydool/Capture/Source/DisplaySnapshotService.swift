import AppKit
import ScreenCaptureKit

struct DisplaySnapshot {
    let screen: NSScreen
    let image: CGImage
}

enum SnapshotFailure: LocalizedError {
    case permissionDenied
    case noDisplays
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            L("Rydool needs Screen Recording permission to capture your screen.")
        case .noDisplays:
            L("Rydool couldn't find a display to capture. If you just connected or disconnected a monitor, try again.")
        case .failed:
            L("Rydool couldn't capture the screen. Please try again.")
        }
    }
}

/// A replaceable source makes capture orchestration independent of ScreenCaptureKit.
@MainActor
protocol DisplaySnapshotSource: AnyObject {
    func prepare() async throws
    func capture() async throws -> [DisplaySnapshot]
    func invalidate()
}

@MainActor
final class DisplaySnapshotService {
    static let shared = DisplaySnapshotService(source: SystemSnapshotSource())
    private let source: any DisplaySnapshotSource
    private var displayObserver: NSObjectProtocol?

    init(source: any DisplaySnapshotSource) {
        self.source = source
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.source.invalidate()
                self?.warmUp()
            }
        }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    func warmUp() {
        guard ScreenAccess.isGranted else { return }
        Task { try? await source.prepare() }
    }

    func captureDisplays() async throws -> [DisplaySnapshot] {
        do {
            return try await source.capture()
        } catch SnapshotFailure.permissionDenied {
            throw SnapshotFailure.permissionDenied
        } catch {
            // The display topology can change between discovery and capture.
            source.invalidate()
            return try await source.capture()
        }
    }
}

@MainActor
private final class SystemSnapshotSource: DisplaySnapshotSource {
    private var cached: [SCDisplay]?

    func invalidate() { cached = nil }

    func prepare() async throws {
        _ = try await availableDisplays()
    }

    private func availableDisplays() async throws -> [SCDisplay] {
        if let cached { return cached }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cached = content.displays
            return content.displays
        } catch {
            guard ScreenAccess.isGranted else { throw SnapshotFailure.permissionDenied }
            throw SnapshotFailure.failed(error)
        }
    }

    func capture() async throws -> [DisplaySnapshot] {
        let displays = try await availableDisplays()
        let byID = displays.reduce(into: [CGDirectDisplayID: SCDisplay]()) { result, display in
            if result[display.displayID] == nil { result[display.displayID] = display }
        }
        let pairs: [(NSScreen, SCDisplay)] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID, let display = byID[id] else { return nil }
            return (screen, display)
        }
        guard !pairs.isEmpty else { throw SnapshotFailure.noDisplays }

        let images = try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
            for (index, pair) in pairs.enumerated() {
                let display = pair.1
                let size = pair.0.frame.size
                let scale = pair.0.backingScaleFactor
                group.addTask {
                    let config = SCStreamConfiguration()
                    config.width = Int((size.width * scale).rounded())
                    config.height = Int((size.height * scale).rounded())
                    config.captureResolution = .best
                    config.showsCursor = false
                    config.scalesToFit = false
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (index, image)
                }
            }
            var completed: [(Int, CGImage)] = []
            for try await item in group { completed.append(item) }
            return completed.sorted { $0.0 < $1.0 }
        }
        return images.map { DisplaySnapshot(screen: pairs[$0.0].0, image: $0.1) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
