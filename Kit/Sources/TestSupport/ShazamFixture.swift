import Foundation
import SQLiteLite

/// Builds a fake Shazam group container with a Core Data-like schema.
public final class ShazamFixture {
    public let container: URL
    public var dbURL: URL { container.appendingPathComponent("com.shazam.mac.Shazam/ShazamDataModel.sqlite") }
    public private(set) var db: SQLiteDatabase?
    private var nextPK: Int64 = 1

    public init(createContainer: Bool = true) throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("shazam-fixture-\(UUID().uuidString)")
        if createContainer {
            try FileManager.default.createDirectory(
                at: container.appendingPathComponent("com.shazam.mac.Shazam"), withIntermediateDirectories: true)
        }
    }

    @discardableResult
    public func createDatabase(wal: Bool = true, dropColumn: String? = nil) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: dbURL.path, mode: .readWriteCreate)
        if wal { try db.execute("PRAGMA journal_mode=WAL") }
        let artistCols = dropColumn == "ZNAME" ? "Z_PK INTEGER PRIMARY KEY, ZTAGRESULT INTEGER" : "Z_PK INTEGER PRIMARY KEY, ZTAGRESULT INTEGER, ZNAME TEXT"
        try db.execute("""
            CREATE TABLE ZSHTAGRESULTMO(Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZTRACKNAME TEXT);
            CREATE TABLE ZSHARTISTMO(\(artistCols));
            CREATE TABLE ZSHMETADATAMO(Z_PK INTEGER PRIMARY KEY, ZTAGRESULT INTEGER, ZKEY TEXT, ZVALUE TEXT);
            """)
        self.db = db
        return db
    }

    /// `date` is a normal Date; stored as Core Data reference time like Shazam does.
    @discardableResult
    public func addTag(title: String?, artists: [String], album: String?, date: Date) throws -> Int64 {
        guard let db = self.db else { throw CocoaError(.fileNoSuchFile) }
        let pk = nextPK; nextPK += 1
        try db.query("INSERT INTO ZSHTAGRESULTMO VALUES(?,?,?)",
                     [.integer(pk), .real(date.timeIntervalSinceReferenceDate), title.map(SQLiteValue.text) ?? .null])
        for (i, artist) in artists.enumerated() {
            try db.query("INSERT INTO ZSHARTISTMO(Z_PK, ZTAGRESULT, ZNAME) VALUES(?,?,?)",
                         [.integer(pk * 100 + Int64(i)), .integer(pk), .text(artist)])
        }
        try db.query("INSERT INTO ZSHMETADATAMO VALUES(?,?,?,?)",
                     [.integer(pk * 100), .integer(pk), .text("Genre"), .text("Electronic")])
        if let album {
            try db.query("INSERT INTO ZSHMETADATAMO VALUES(?,?,?,?)",
                         [.integer(pk * 100 + 1), .integer(pk), .text("Album"), .text(album)])
        }
        return pk
    }

    public func remove() { try? FileManager.default.removeItem(at: container) }
}
