import Foundation
import os
import ScrobbleCore
import SQLiteLite

/// The only code allowed to touch Shazam's container (see scripts/check-boundaries.sh).
/// Opens the database read-only; never writes, never uses the network.
public struct ShazamLibrary: TagSource {
    public static let defaultContainerURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Group Containers/4GWDBCF5A4.group.com.shazam")
    public static let defaultShazamAppURL = URL(fileURLWithPath: "/Applications/Shazam.app")
    public static let watchedFileNames = ["ShazamDataModel.sqlite", "ShazamDataModel.sqlite-wal"]

    public let containerURL: URL
    public let shazamAppURL: URL
    public var watchedDirectoryURL: URL { containerURL.appendingPathComponent("com.shazam.mac.Shazam") }
    public var databaseURL: URL { watchedDirectoryURL.appendingPathComponent("ShazamDataModel.sqlite") }

    private static let log = Logger(subsystem: "ShazamScrobbler", category: "shazam")
    private static let requiredColumns: [(table: String, columns: [String])] = [
        ("ZSHTAGRESULTMO", ["Z_PK", "ZDATE", "ZTRACKNAME"]),
        ("ZSHARTISTMO", ["Z_PK", "ZTAGRESULT", "ZNAME"]),
        ("ZSHMETADATAMO", ["Z_PK", "ZTAGRESULT", "ZKEY", "ZVALUE"]),
    ]

    /// The only public way in: always Shazam's real container, never a caller-chosen path.
    public init() {
        self.init(containerURL: Self.defaultContainerURL, shazamAppURL: Self.defaultShazamAppURL)
    }

    /// Internal so only tests (via `@testable import`) can point the reader elsewhere.
    init(containerURL: URL, shazamAppURL: URL = ShazamLibrary.defaultShazamAppURL) {
        self.containerURL = containerURL
        self.shazamAppURL = shazamAppURL
    }

    public func read(since: Date, recentLimit: Int) -> TagSourceResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: containerURL.path) else {
            return TagSourceResult(status: fm.fileExists(atPath: shazamAppURL.path) ? .noLibraryYet : .notInstalled)
        }
        do {
            let db = try SQLiteDatabase(path: databaseURL.path, mode: .readOnly)
            if let missing = try Self.schemaProblem(db) {
                Self.log.error("Unsupported Shazam schema, missing \(missing, privacy: .public)")
                return TagSourceResult(status: .unsupportedSchema(missing))
            }
            // Fetch twice the limit: rows without an artist are dropped in Swift after the cheap top-N selection.
            let recent = Array(try Self.tags(db, filter: "1=1", bindings: [], ascending: false,
                                             limit: max(recentLimit, 0) * 2).prefix(max(recentLimit, 0)))
            guard !recent.isEmpty else { return TagSourceResult(status: .noLibraryYet) }
            // Capped: a backlog larger than this is picked up by later scans as the caller's cursor advances.
            let since = try Self.tags(db, filter: "ZDATE > ?", bindings: [.real(since.timeIntervalSinceReferenceDate)],
                                      ascending: true, limit: Self.sinceCap)
            return TagSourceResult(status: .ok, tagsSince: since, recent: recent)
        } catch let error as SQLiteError {
            return TagSourceResult(status: classify(error))
        } catch {
            return TagSourceResult(status: .unreadable(String(describing: error)))
        }
    }

    public func tags(withPKs pks: [Int64]) throws -> [Int64: ShazamTag] {
        guard !pks.isEmpty else { return [:] }
        let db = try SQLiteDatabase(path: databaseURL.path, mode: .readOnly)
        let placeholders = Array(repeating: "?", count: pks.count).joined(separator: ",")
        let found = try Self.tags(db, filter: "Z_PK IN (\(placeholders))", bindings: pks.map { .integer($0) },
                                  ascending: true, limit: pks.count)
        return Dictionary(found.map { ($0.pk, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func classify(_ error: SQLiteError) -> LibraryStatus {
        if error.isPermissionDenied {
            Self.log.notice("Shazam database read refused: \(error.description, privacy: .public)")
            return .accessDenied
        }
        if !FileManager.default.fileExists(atPath: databaseURL.path) { return .noLibraryYet }
        Self.log.error("Shazam database unreadable: \(error.description, privacy: .public)")
        return .unreadable(error.description)
    }

    private static let sinceCap = 5000
    /// Valid ZDATE window in seconds since 2001 (about 2001...2127); anything else is corrupt and ignored.
    private static let dateRange: (lower: Double, upper: Double) = (0, 4e9)

    private static func schemaProblem(_ db: SQLiteDatabase) throws -> String? {
        for (table, columns) in requiredColumns {
            let kind = try db.query("SELECT type FROM sqlite_master WHERE name = ?", [.text(table)]).first?.string("type")
            if let kind, kind != "table" { return "\(table) is not a table" }
            let present = Set(try db.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") })
            if present.isEmpty { return table }
            if let missing = columns.first(where: { !present.contains($0) }) { return "\(table).\(missing)" }
        }
        return nil
    }

    /// Picks the top `limit` tags first (a derived table), then looks up artist and album for only those rows, so
    /// cost is independent of library size even though Shazam's tables have no indexes on the foreign keys.
    /// `filter` refers to unqualified ZSHTAGRESULTMO columns.
    private static func tags(_ db: SQLiteDatabase, filter: String, bindings: [SQLiteValue],
                             ascending: Bool, limit: Int) throws -> [ShazamTag] {
        let dir = ascending ? "ASC" : "DESC"
        let sql = """
            SELECT t.pk, t.date, t.title,
              (SELECT a.ZNAME FROM ZSHARTISTMO a WHERE a.ZTAGRESULT = t.pk ORDER BY a.Z_PK LIMIT 1) AS artist,
              (SELECT m.ZVALUE FROM ZSHMETADATAMO m WHERE m.ZTAGRESULT = t.pk AND m.ZKEY = 'Album'
                 ORDER BY m.Z_PK LIMIT 1) AS album
            FROM (SELECT Z_PK AS pk, ZDATE AS date, ZTRACKNAME AS title FROM ZSHTAGRESULTMO
                  WHERE \(filter) AND ZTRACKNAME IS NOT NULL AND ZTRACKNAME <> '' AND ZDATE BETWEEN ? AND ?
                  ORDER BY ZDATE \(dir), Z_PK \(dir) LIMIT ?) t
            ORDER BY t.date \(dir), t.pk \(dir)
            """
        let all = bindings + [.real(dateRange.lower), .real(dateRange.upper), .integer(Int64(limit))]
        return try db.query(sql, all).compactMap { row in
            guard let pk = row.int("pk"), let seconds = row.double("date"), seconds.isFinite,
                  let title = row.string("title"), let artist = row.string("artist"), !artist.isEmpty else { return nil }
            let album = row.string("album").flatMap { $0.isEmpty ? nil : $0 }
            return ShazamTag(pk: pk, date: Date(timeIntervalSinceReferenceDate: seconds),
                             track: Track(artist: artist, title: title, album: album))
        }
    }
}
