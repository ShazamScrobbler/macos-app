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
    public func createDatabase(wal: Bool = true, dropColumn: String? = nil, tagResultAsView: Bool = false) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: dbURL.path, mode: .readWriteCreate)
        if wal { try db.execute("PRAGMA journal_mode=WAL") }
        let artistCols = dropColumn == "ZNAME" ? "Z_PK INTEGER PRIMARY KEY, ZTAGRESULT INTEGER" : "Z_PK INTEGER PRIMARY KEY, ZTAGRESULT INTEGER, ZNAME TEXT"
        try db.execute("""
            \(tagResultAsView
                ? "CREATE TABLE TAGBASE(Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZTRACKNAME TEXT); CREATE VIEW ZSHTAGRESULTMO AS SELECT * FROM TAGBASE;"
                : "CREATE TABLE ZSHTAGRESULTMO(Z_PK INTEGER PRIMARY KEY, ZDATE TIMESTAMP, ZTRACKNAME TEXT);")
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

    /// Inserts a tag whose ZDATE is stored verbatim (reference-time seconds), for malformed-date tests.
    @discardableResult
    public func addTag(title: String, artist: String, rawSeconds: Double) throws -> Int64 {
        guard let db = self.db else { throw CocoaError(.fileNoSuchFile) }
        let pk = nextPK; nextPK += 1
        try db.query("INSERT INTO ZSHTAGRESULTMO VALUES(?,?,?)", [.integer(pk), .real(rawSeconds), .text(title)])
        try db.query("INSERT INTO ZSHARTISTMO(Z_PK, ZTAGRESULT, ZNAME) VALUES(?,?,?)",
                     [.integer(pk * 100), .integer(pk), .text(artist)])
        return pk
    }

    /// Bulk-fills `count` tags, each with one artist and `metadataPerTag` metadata rows, in one transaction.
    public func addBulk(count: Int, metadataPerTag: Int, start: Date) throws {
        guard let db = self.db else { throw CocoaError(.fileNoSuchFile) }
        try db.transaction {
            for i in 0..<count {
                let pk = nextPK; nextPK += 1
                try db.query("INSERT INTO ZSHTAGRESULTMO VALUES(?,?,?)",
                             [.integer(pk), .real(start.timeIntervalSinceReferenceDate + Double(i)), .text("Title \(i)")])
                try db.query("INSERT INTO ZSHARTISTMO(Z_PK, ZTAGRESULT, ZNAME) VALUES(?,?,?)",
                             [.integer(pk * 100), .integer(pk), .text("Artist \(i)")])
                for m in 0..<metadataPerTag {
                    try db.query("INSERT INTO ZSHMETADATAMO VALUES(?,?,?,?)",
                                 [.integer(pk * 100 + Int64(m)), .integer(pk), .text(m == 0 ? "Album" : "Key\(m)"), .text("v\(m)")])
                }
            }
        }
    }

    public func remove() { try? FileManager.default.removeItem(at: container) }
}
