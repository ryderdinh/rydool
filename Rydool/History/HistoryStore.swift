import Foundation
import CryptoKit
import SQLite3
import ImageIO
import UniformTypeIdentifiers

struct HistoryItem: Identifiable, Equatable {
    let id: String
    let kind: Kind
    let data: Data
    let byteCount: Int
    let copiedAt: Date
    let isPinned: Bool
    let sourceBundleID: String?

    enum Kind: String { case text, image }
    var text: String? { kind == .text ? String(data: data, encoding: .utf8) : nil }
}

enum HistoryStoreError: LocalizedError {
    case database(String)
    case capacity
    var errorDescription: String? {
        switch self {
        case .database: return L("Couldn't access clipboard history. Check storage space and permissions.")
        case .capacity: return L("History is full; unpin or delete items before saving more.")
        }
    }
}

/// All mutations and quota enforcement are serialized by the main actor. Payloads and
/// metadata live in the same SQLite transaction so a failed write cannot orphan files.
@MainActor
final class HistoryStore {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            if let db { sqlite3_close(db) }
            db = nil
            throw HistoryStoreError.database(message)
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let versionStatement = try prepare("PRAGMA user_version")
            guard sqlite3_step(versionStatement) == SQLITE_ROW else { sqlite3_finalize(versionStatement); throw failure() }
            let version = sqlite3_column_int(versionStatement, 0)
            sqlite3_finalize(versionStatement)
            guard version <= 2 else { throw HistoryStoreError.database("Unsupported future schema") }
            try execute("PRAGMA secure_delete=ON")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload BLOB NOT NULL, digest TEXT NOT NULL, copied REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source TEXT)")
            let columns = try prepare("PRAGMA table_info(history)")
            var hasThumbnail = false
            while sqlite3_step(columns) == SQLITE_ROW {
                if let name = sqlite3_column_text(columns, 1), String(cString: name) == "thumbnail" { hasThumbnail = true }
            }
            sqlite3_finalize(columns)
            if !hasThumbnail { try execute("ALTER TABLE history ADD COLUMN thumbnail BLOB") }
            try execute("CREATE INDEX IF NOT EXISTS history_digest ON history(digest)")
            try execute("PRAGMA user_version=2")
        } catch {
            if let db { sqlite3_close(db) }
            db = nil
            throw error
        }
    }

    deinit { if let db { sqlite3_close(db) } }

    func all() throws -> [HistoryItem] {
        let statement = try prepare("SELECT id, kind, CASE WHEN kind='image' THEN thumbnail ELSE payload END, copied, pinned, source, length(payload) FROM history ORDER BY pinned DESC, copied DESC, rowid DESC")
        defer { sqlite3_finalize(statement) }
        var result: [HistoryItem] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            guard let id = sqlite3_column_text(statement, 0), let rawKind = sqlite3_column_text(statement, 1),
                  let kind = HistoryItem.Kind(rawValue: String(cString: rawKind)) else { throw failure() }
            let size = Int(sqlite3_column_bytes(statement, 2))
            let data: Data
            if size == 0 { data = Data() }
            else if let bytes = sqlite3_column_blob(statement, 2) { data = Data(bytes: bytes, count: size) }
            else { throw failure() }
            let source = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            result.append(HistoryItem(id: String(cString: id), kind: kind, data: data,
                                      byteCount: Int(sqlite3_column_int64(statement, 6)), copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                                      isPinned: sqlite3_column_int(statement, 4) != 0, sourceBundleID: source))
        }
        return result
    }

    func insert(kind: HistoryItem.Kind, data: Data, source: String?, maxItems: Int, maxBytes: Int, now: Date = Date()) throws {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data).map { String(format: "%02x", $0) }.joined()
        try transaction {
            let existingID = try matchingID(kind: kind, data: data, digest: digest)
            let insertedID = existingID ?? UUID().uuidString
            if let existingID {
                let stmt = try prepare("UPDATE history SET copied=?, source=? WHERE id=?")
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
                bind(source, to: stmt, at: 2)
                bind(existingID, to: stmt, at: 3)
                try stepDone(stmt)
            } else {
                let stmt = try prepare("INSERT INTO history(id,kind,payload,digest,copied,source,thumbnail) VALUES(?,?,?,?,?,?,?)")
                defer { sqlite3_finalize(stmt) }
                bind(insertedID, to: stmt, at: 1)
                bind(kind.rawValue, to: stmt, at: 2)
                _ = data.withUnsafeBytes { bytes in sqlite3_bind_blob(stmt, 3, bytes.baseAddress, Int32(bytes.count), transient) }
                bind(digest, to: stmt, at: 4)
                sqlite3_bind_double(stmt, 5, now.timeIntervalSince1970)
                bind(source, to: stmt, at: 6)
                if kind == .image, let thumbnail = Self.thumbnail(data) {
                    _ = thumbnail.withUnsafeBytes { sqlite3_bind_blob(stmt, 7, $0.baseAddress, Int32($0.count), transient) }
                } else { sqlite3_bind_null(stmt, 7) }
                try stepDone(stmt)
            }
            try enforce(maxItems: maxItems, maxBytes: maxBytes, protecting: insertedID)
        }
    }

    func setPinned(_ pinned: Bool, id: String, maxItems: Int, maxBytes: Int) throws {
        try transaction {
            let stmt = try prepare("UPDATE history SET pinned=? WHERE id=?")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
            bind(id, to: stmt, at: 2)
            try stepDone(stmt)
            try enforce(maxItems: maxItems, maxBytes: maxBytes, protecting: nil)
        }
    }

    func touch(id: String, at date: Date = Date()) throws {
        let stmt = try prepare("UPDATE history SET copied=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        bind(id, to: stmt, at: 2)
        try stepDone(stmt)
    }

    func delete(id: String) throws {
        let stmt = try prepare("DELETE FROM history WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id, to: stmt, at: 1)
        try stepDone(stmt)
    }

    func clear() throws { try execute("DELETE FROM history") }

    func enforceLimits(maxItems: Int, maxBytes: Int) throws {
        try transaction { try enforce(maxItems: maxItems, maxBytes: maxBytes, protecting: nil) }
    }

    private func enforce(maxItems: Int, maxBytes: Int, protecting: String?) throws {
        var items = try all()
        var bytes = items.reduce(0) { $0 + $1.byteCount }
        while items.filter({ !$0.isPinned }).count > max(0, maxItems) || bytes > max(0, maxBytes) {
            guard let victim = items.reversed().first(where: { !$0.isPinned && $0.id != protecting }) else {
                throw HistoryStoreError.capacity
            }
            try delete(id: victim.id)
            bytes -= victim.byteCount
            items.removeAll { $0.id == victim.id }
        }
    }

    func payload(id: String) throws -> Data? {
        let stmt = try prepare("SELECT payload FROM history WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id, to: stmt, at: 1)
        let status = sqlite3_step(stmt)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw failure() }
        let count = Int(sqlite3_column_bytes(stmt, 0))
        guard count > 0, let bytes = sqlite3_column_blob(stmt, 0) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func matchingID(kind: HistoryItem.Kind, data: Data, digest: String) throws -> String? {
        let stmt = try prepare("SELECT id,payload FROM history WHERE kind=? AND digest=?")
        defer { sqlite3_finalize(stmt) }
        bind(kind.rawValue, to: stmt, at: 1)
        bind(digest, to: stmt, at: 2)
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW else { throw failure() }
            let count = Int(sqlite3_column_bytes(stmt, 1))
            if count == data.count, let bytes = sqlite3_column_blob(stmt, 1),
               Data(bytes: bytes, count: count) == data, let id = sqlite3_column_text(stmt, 0) {
                return String(cString: id)
            }
        }
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try work(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw failure() }
    }
    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        if let value { sqlite3_bind_text(statement, index, value, -1, transient) }
        else { sqlite3_bind_null(statement, index) }
    }
    private func failure() -> HistoryStoreError {
        .database(db.map { String(cString: sqlite3_errmsg($0)) } ?? "closed")
    }
}
