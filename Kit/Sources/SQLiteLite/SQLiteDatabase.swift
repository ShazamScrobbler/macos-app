import Foundation
import SQLite3

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

public struct SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int32
    public let extendedCode: Int32
    public let systemErrno: Int32
    public let message: String

    /// macOS privacy refusals surface as EPERM from open(2); plain file permissions as EACCES.
    public var isPermissionDenied: Bool {
        code == SQLITE_AUTH || code == SQLITE_PERM || systemErrno == EPERM || systemErrno == EACCES
    }
    public var isBusy: Bool { code == SQLITE_BUSY || code == SQLITE_LOCKED }
    public var description: String { "SQLite \(code)/\(extendedCode) errno=\(systemErrno): \(message)" }
}

public struct SQLiteRow: Sendable {
    let values: [String: SQLiteValue]
    public subscript(_ column: String) -> SQLiteValue { values[column] ?? .null }
    public func string(_ column: String) -> String? {
        if case let .text(s) = self[column] { return s }
        return nil
    }
    public func int(_ column: String) -> Int64? {
        switch self[column] {
        case let .integer(i): return i
        case let .real(d): return Int64(d)
        default: return nil
        }
    }
    public func double(_ column: String) -> Double? {
        switch self[column] {
        case let .real(d): return d
        case let .integer(i): return Double(i)
        default: return nil
        }
    }
}

/// One connection. Calls are serialized with a lock; callers own higher-level concurrency.
public final class SQLiteDatabase: @unchecked Sendable {
    public enum Mode: Sendable { case readOnly, readWriteCreate, inMemory }

    private let handle: OpaquePointer?
    private let lock = NSLock()

    public init(path: String, mode: Mode, busyTimeoutMs: Int32 = 2000) throws {
        let flags: Int32 = mode == .readOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        var openPath = mode == .inMemory ? ":memory:" : path
        if mode == .readOnly {
            // NOFOLLOW makes SQLite refuse a symlink anywhere in the path (macOS puts /var, /tmp behind symlinks), so
            // canonicalize the directory and let NOFOLLOW guard only the final component: the database file itself.
            // (Foundation's resolvingSymlinksInPath maps /private/var back to /var, so use realpath(3).)
            let url = URL(fileURLWithPath: path)
            if let resolved = realpath(url.deletingLastPathComponent().path, nil) {
                openPath = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent(url.lastPathComponent).path
                free(resolved)
            }
        }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(openPath, &db, flags, nil)
        guard rc == SQLITE_OK else {
            let error = Self.error(db, rc)
            sqlite3_close_v2(db)
            throw error
        }
        sqlite3_extended_result_codes(db, 1)
        sqlite3_busy_timeout(db, busyTimeoutMs)
        handle = db
        if mode == .readOnly {
            // sqlite3_db_config(TRUSTED_SCHEMA/DEFENSIVE) is variadic and unavailable from Swift; the PRAGMAs are the
            // equivalents that matter for a read-only connection to a file we don't own.
            try execute("PRAGMA trusted_schema=OFF")
            try execute("PRAGMA query_only=ON")
        }
    }

    deinit { sqlite3_close_v2(handle) }

    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw Self.error(handle, rc) }
    }

    @discardableResult
    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        var rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw Self.error(handle, rc) }
        defer { sqlite3_finalize(stmt) }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null: rc = sqlite3_bind_null(stmt, index)
            case let .integer(n): rc = sqlite3_bind_int64(stmt, index, n)
            case let .real(d): rc = sqlite3_bind_double(stmt, index, d)
            case let .text(s): rc = sqlite3_bind_text(stmt, index, s, -1, sqliteTransient)
            }
            guard rc == SQLITE_OK else { throw Self.error(handle, rc) }
        }
        var rows: [SQLiteRow] = []
        while true {
            rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw Self.error(handle, rc) }
            var values: [String: SQLiteValue] = [:]
            for column in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, column))
                switch sqlite3_column_type(stmt, column) {
                case SQLITE_INTEGER: values[name] = .integer(sqlite3_column_int64(stmt, column))
                case SQLITE_FLOAT: values[name] = .real(sqlite3_column_double(stmt, column))
                case SQLITE_TEXT: values[name] = .text(String(cString: sqlite3_column_text(stmt, column)))
                default: values[name] = .null
                }
            }
            rows.append(SQLiteRow(values: values))
        }
        return rows
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    static func error(_ db: OpaquePointer?, _ rc: Int32) -> SQLiteError {
        SQLiteError(
            code: rc & 0xFF,
            extendedCode: db.map { sqlite3_extended_errcode($0) } ?? rc,
            systemErrno: db.map { sqlite3_system_errno($0) } ?? 0,
            message: db.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(rc))
        )
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
