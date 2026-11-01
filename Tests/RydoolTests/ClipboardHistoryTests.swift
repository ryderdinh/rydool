import XCTest
import AppKit
@testable import Rydool

final class ClipboardHistoryTests: XCTestCase {
    func testRelativeTimeNeverDisplaysSeconds() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertEqual(HistoryRelativeTime.string(since: now.addingTimeInterval(-59), now: now, language: .english), "Just now")
        XCTAssertEqual(HistoryRelativeTime.string(since: now.addingTimeInterval(-119), now: now, language: .vietnamese), "1 phút trước")
        XCTAssertEqual(HistoryRelativeTime.string(since: now.addingTimeInterval(-3_600), now: now, language: .simplifiedChinese), "1 小时前")
        XCTAssertEqual(HistoryRelativeTime.string(since: now.addingTimeInterval(-86_400), now: now, language: .english), "1 day ago")
    }
    @MainActor func testPauseSensitiveMarkersExclusionsAndOwnCopy() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RydoolTests.\(id)"))
        defer { defaults.removePersistentDomain(forName: "RydoolTests.\(id)"); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name("RydoolTests.\(id)"))
        defer { board.releaseGlobally() }
        defaults.set(false, forKey: "clipboardTracking")
        var app: String? = "example.editor"
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false, sourceApp: { app })
        func put(_ text: String, concealed: Bool = false) {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if concealed { item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
            board.writeObjects([item])
        }
        put("before resume"); history.poll(); await history.waitForPendingWork(); XCTAssertTrue(history.items.isEmpty)
        history.tracking = true; history.poll(); await history.waitForPendingWork(); XCTAssertTrue(history.items.isEmpty)
        put("alpha"); history.poll(); await history.waitForPendingWork(); XCTAssertEqual(history.items.map(\.text), ["alpha"])
        put("secret", concealed: true); history.poll(); await history.waitForPendingWork(); XCTAssertEqual(history.items.map(\.text), ["alpha"])
        history.tracking = false; put("paused"); history.poll(); await history.waitForPendingWork(); history.tracking = true; history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.map(\.text), ["alpha"])
        history.excludedApps = "example.password"
        app = "example.password"; put("excluded"); history.poll(); await history.waitForPendingWork()
        app = nil; put("unknown"); history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.map(\.text), ["alpha"])
        app = "example.editor"
        let alpha = try XCTUnwrap(history.items.first)
        history.copy(alpha); history.poll(); await history.waitForPendingWork(); XCTAssertEqual(history.items.count, 1)
        put("external"); history.poll(); await history.waitForPendingWork(); XCTAssertEqual(Set(history.items.compactMap(\.text)), Set(["alpha", "external"]))
    }

    @MainActor func testHistoryDefaultsOnAndRemembersPause() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let suite = "RydoolTests.\(id)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name(suite))
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("before launch", forType: .string)
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false)
        XCTAssertTrue(history.tracking)
        history.poll(); await history.waitForPendingWork()
        XCTAssertTrue(history.items.isEmpty, "The clipboard that existed at startup must not be captured")
        board.clearContents(); board.setString("after launch", forType: .string)
        history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.map(\.text), ["after launch"])
        history.tracking = false
        let restarted = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false)
        XCTAssertFalse(restarted.tracking, "A deliberate pause must survive restart")
        board.clearContents(); board.setString("while paused", forType: .string)
        restarted.poll(); await restarted.waitForPendingWork()
        XCTAssertEqual(restarted.items.map(\.text), ["after launch"])
    }

    @MainActor func testExcludedApplicationsPreserveExistingEntriesAndCanBeRemoved() throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let suite = "RydoolTests.\(id)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name(suite))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false)
        history.excludedApps = "legacy.unknown\n"

        let app = directory.appendingPathComponent("Example App.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let bundleID = "example.rydool-test.\(id)"
        let info: [String: String] = ["CFBundleIdentifier": bundleID, "CFBundleName": "Example App", "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(history.addExcludedApplications([app, app]), 0)
        XCTAssertEqual(history.excludedApplicationIDs, ["legacy.unknown", bundleID])
        XCTAssertEqual(history.excludedApplicationURL(bundleID)?.standardizedFileURL, app.standardizedFileURL)
        XCTAssertEqual(history.addExcludedApplications([directory]), 1)
        XCTAssertEqual(history.excludedApplicationIDs, ["legacy.unknown", bundleID])

        let restarted = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false)
        XCTAssertEqual(restarted.excludedApplicationIDs, ["legacy.unknown", bundleID])
        try FileManager.default.removeItem(at: app)
        XCTAssertNil(restarted.excludedApplicationURL(bundleID))
        XCTAssertEqual(restarted.excludedApplicationLastKnownName(bundleID), "Example App")
        restarted.removeExcludedApplication(bundleID)
        XCTAssertEqual(restarted.excludedApplicationIDs, ["legacy.unknown"])
        XCTAssertNil(restarted.excludedApplicationLastKnownName(bundleID))
    }
    @MainActor func testScreenshotIsRecordedOnceAndRespectsPause() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RydoolTests.\(id)"))
        defer { defaults.removePersistentDomain(forName: "RydoolTests.\(id)"); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name("RydoolTests.\(id)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false, sourceApp: { "example.editor" })
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        history.tracking = true
        let firstOwnership = board.clearContents(); board.setData(png, forType: .png)
        history.recordScreenshot(png, source: "example.editor", ownershipCount: firstOwnership)
        history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.kind, .image)
        XCTAssertTrue(history.copy(try XCTUnwrap(history.items.first)))
        XCTAssertNotNil(board.data(forType: .tiff))
        history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.count, 1)
        history.tracking = false
        history.clear()
        let pausedOwnership = board.clearContents(); board.setData(png, forType: .png)
        history.recordScreenshot(png, source: "example.editor", ownershipCount: pausedOwnership); history.poll(); await history.waitForPendingWork()
        XCTAssertTrue(history.items.isEmpty)
    }

    @MainActor func testExternalCopyAfterScreenshotIsNotSwallowed() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RydoolTests.\(id)"))
        defer { defaults.removePersistentDomain(forName: "RydoolTests.\(id)"); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name("RydoolTests.\(id)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false, sourceApp: { "example.editor" })
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        history.tracking = true
        let owner = board.clearContents(); board.setData(png, forType: .png)
        board.clearContents(); board.setString("external after screenshot", forType: .string)
        history.recordScreenshot(png, source: "example.editor", ownershipCount: owner)
        history.poll(); await history.waitForPendingWork()
        XCTAssertEqual(history.items.count, 2)
        XCTAssertTrue(history.items.contains { $0.text == "external after screenshot" })
        XCTAssertTrue(history.items.contains { $0.kind == .image })
    }

    @MainActor func testPauseAndClearInvalidatePendingClipboardWrites() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RydoolTests.\(id)"))
        defer { defaults.removePersistentDomain(forName: "RydoolTests.\(id)"); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name("RydoolTests.\(id)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false, sourceApp: { "example.editor" })
        history.tracking = true
        board.clearContents(); board.setString("pending pause", forType: .string); history.poll()
        history.tracking = false
        await history.waitForPendingWork()
        XCTAssertTrue(history.items.isEmpty)
        history.tracking = true
        board.clearContents(); board.setString("pending clear", forType: .string); history.poll()
        history.clear()
        await history.waitForPendingWork()
        XCTAssertTrue(history.items.isEmpty)
    }

    @MainActor func testQueuedCopiesRetainOrder() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RydoolTests.\(id)"))
        defer { defaults.removePersistentDomain(forName: "RydoolTests.\(id)"); try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name("RydoolTests.\(id)"))
        defer { board.releaseGlobally() }
        let history = ClipboardHistory(pasteboard: board, defaults: defaults, storeURL: directory.appendingPathComponent("db.sqlite"), startTimer: false, sourceApp: { "example.editor" })
        history.tracking = true
        board.clearContents(); board.setString("first", forType: .string); history.poll()
        board.clearContents(); board.setString("second", forType: .string); history.poll()
        await history.waitForPendingWork()
        XCTAssertEqual(history.items.map(\.text), ["second", "first"])
    }

}
