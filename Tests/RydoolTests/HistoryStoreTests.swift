import XCTest
import AppKit
import SQLite3
import Darwin
@testable import Rydool

final class HistoryStoreTests: XCTestCase {
    @MainActor func testPersistenceDedupAndPinnedQuota() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let store = try HistoryStore(url: url)
        let a = Data("alpha".utf8), b = Data("beta".utf8), c = Data("gamma".utf8)
        try store.insert(kind: .text, data: a, source: nil, maxItems: 1, maxBytes: 100, now: Date(timeIntervalSince1970: 1))
        let id = try XCTUnwrap(store.all().first?.id)
        try store.setPinned(true, id: id, maxItems: 1, maxBytes: 100)
        try store.insert(kind: .text, data: a, source: nil, maxItems: 1, maxBytes: 100, now: Date(timeIntervalSince1970: 2))
        try store.insert(kind: .text, data: b, source: nil, maxItems: 1, maxBytes: 100, now: Date(timeIntervalSince1970: 3))
        try store.insert(kind: .text, data: c, source: nil, maxItems: 1, maxBytes: 100, now: Date(timeIntervalSince1970: 4))
        let items = try HistoryStore(url: url).all()
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.id == id && $0.isPinned && $0.data == a })
        XCTAssertTrue(items.contains { $0.data == c })
        XCTAssertFalse(items.contains { $0.data == b })
    }

    @MainActor func testCapacityFailureRollsBackWithoutDeletingPinnedItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        try store.insert(kind: .text, data: Data("keep".utf8), source: nil, maxItems: 10, maxBytes: 5)
        let id = try XCTUnwrap(store.all().first?.id)
        try store.setPinned(true, id: id, maxItems: 10, maxBytes: 5)
        XCTAssertThrowsError(try store.insert(kind: .text, data: Data("new".utf8), source: nil, maxItems: 10, maxBytes: 5))
        XCTAssertEqual(try store.all().map(\.text), ["keep"])
        try store.clear()
        XCTAssertTrue(try store.all().isEmpty)
    }
    @MainActor func testImagePayloadPersistsAndDeduplicatesWithoutLoadingFullImagesIntoList() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try store.insert(kind: .image, data: data, source: nil, maxItems: 10, maxBytes: 10_000_000)
        try store.insert(kind: .image, data: data, source: nil, maxItems: 10, maxBytes: 10_000_000)
        let item = try XCTUnwrap(store.all().first)
        XCTAssertEqual(try store.all().count, 1)
        XCTAssertEqual(try store.payload(id: item.id), data)
        XCTAssertEqual(item.byteCount, data.count)
        let thumbnail = try XCTUnwrap(NSBitmapImageRep(data: item.data))
        XCTAssertLessThanOrEqual(thumbnail.pixelsWide, 128)
    }

    @MainActor func testFutureDatabaseVersionIsNotModified() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("future.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try HistoryStore(url: url))
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), 99)
        sqlite3_finalize(stmt)
        sqlite3_close(db)
    }

    @MainActor func testKilledWriterRollsBackUncommittedTransaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        do {
            let store = try HistoryStore(url: url)
            try store.insert(kind: .text, data: Data("committed".utf8), source: nil, maxItems: 10, maxBytes: 100)
        }
        let ready = directory.appendingPathComponent("writer-ready")
        let code = """
import pathlib, sqlite3, sys, time
connection = sqlite3.connect(sys.argv[1])
connection.execute('BEGIN IMMEDIATE')
connection.execute("INSERT INTO history(id,kind,payload,digest,copied,pinned) VALUES('pending','text',X'70656e64696e67','pending',1,0)")
pathlib.Path(sys.argv[2]).touch()
time.sleep(30)
"""
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        child.arguments = ["python3", "-c", code, url.path, ready.path]
        try child.run()
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline, child.isRunning { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path), "Writer did not reach its uncommitted transaction")
        guard child.isRunning else { XCTFail("Writer exited before termination"); return }
        kill(child.processIdentifier, SIGKILL)
        child.waitUntilExit()
        let reopened = try HistoryStore(url: url)
        XCTAssertEqual(try reopened.all().compactMap(\.text), ["committed"])
    }

    @MainActor func testVersionOneMigrationPreservesRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = """
CREATE TABLE history (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload BLOB NOT NULL, digest TEXT NOT NULL, copied REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source TEXT);
INSERT INTO history(id,kind,payload,digest,copied,pinned) VALUES('old','text',X'6f6c642064617461','old',1,1);
PRAGMA user_version=1;
"""
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let store = try HistoryStore(url: url)
        let item = try XCTUnwrap(store.all().first)
        XCTAssertEqual(item.text, "old data")
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(try store.payload(id: "old"), Data("old data".utf8))
        try store.insert(kind: .text, data: Data("new data".utf8), source: nil, maxItems: 5, maxBytes: 100)
        XCTAssertEqual(try store.all().count, 2)
    }

}
