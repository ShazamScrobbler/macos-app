import Foundation
import SQLite3
import Testing
@testable import SQLiteLite

@Suite struct SQLiteDatabaseTests {
    @Test func roundTripsValuesInMemory() throws {
        let db = try SQLiteDatabase(path: "", mode: .inMemory)
        try db.execute("CREATE TABLE t(i INTEGER, r REAL, s TEXT, n TEXT)")
        try db.query("INSERT INTO t VALUES(?,?,?,?)", [.integer(7), .real(1.5), .text("é ✓"), .null])
        let row = try #require(try db.query("SELECT * FROM t").first)
        #expect(row.int("i") == 7)
        #expect(row.double("r") == 1.5)
        #expect(row.string("s") == "é ✓")
        #expect(row["n"] == .null)
    }

    @Test func missingFileReadOnlyIsCantOpenNotPermission() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        #expect {
            _ = try SQLiteDatabase(path: path, mode: .readOnly)
        } throws: { error in
            let e = error as! SQLiteError
            return e.code == SQLITE_CANTOPEN && !e.isPermissionDenied
        }
    }

    @Test func unreadableFileIsPermissionDenied() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("x.sqlite").path
        do { let db = try SQLiteDatabase(path: path, mode: .readWriteCreate); try db.execute("CREATE TABLE a(b)") }
        chmod(path, 0)
        defer { chmod(path, 0o644) }
        #expect {
            _ = try SQLiteDatabase(path: path, mode: .readOnly).query("SELECT * FROM a")
        } throws: { ($0 as! SQLiteError).isPermissionDenied }
    }

    @Test func transactionRollsBackOnError() throws {
        let db = try SQLiteDatabase(path: "", mode: .inMemory)
        try db.execute("CREATE TABLE t(i INTEGER)")
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try db.transaction { try db.query("INSERT INTO t VALUES(1)"); throw Boom() }
        }
        #expect(try db.query("SELECT COUNT(*) AS c FROM t").first?.int("c") == 0)
    }
}
