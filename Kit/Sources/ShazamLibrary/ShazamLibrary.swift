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

    public init(containerURL: URL = ShazamLibrary.defaultContainerURL,
                shazamAppURL: URL = ShazamLibrary.defaultShazamAppURL) {
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
            let recent = try Self.tags(db, filter: "1=1", bindings: [], ascending: false, limit: recentLimit)
            guard !recent.isEmpty else { return TagSourceResult(status: .noLibraryYet) }
            let since = try Self.tags(db, filter: "t.ZDATE > ?", bindings: [.real(since.timeIntervalSinceReferenceDate)],
                                      ascending: true, limit: nil)
            return TagSourceResult(status: .ok, tagsSince: since, recent: recent)
        } catch let error as SQLiteError {
            return TagSourceResult(status: classify(error))
        } catch {
            return TagSourceResult(status: .unreadable(String(describing: error)))
        }
    }

    public func tags(withPKs pks: [Int64]) -> [Int64: ShazamTag] {
        guard !pks.isEmpty, let db = try? SQLiteDatabase(path: databaseURL.path, mode: .readOnly) else { return [:] }
        let placeholders = Array(repeating: "?", count: pks.count).joined(separator: ",")
        let found = (try? Self.tags(db, filter: "t.Z_PK IN (\(placeholders))", bindings: pks.map { .integer($0) },
                                    ascending: true, limit: nil)) ?? []
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

    private static func schemaProblem(_ db: SQLiteDatabase) throws -> String? {
        for (table, columns) in requiredColumns {
            let present = Set(try db.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") })
            if present.isEmpty { return table }
            if let missing = columns.first(where: { !present.contains($0) }) { return "\(table).\(missing)" }
        }
        return nil
    }

    private static func tags(_ db: SQLiteDatabase, filter: String, bindings: [SQLiteValue],
                             ascending: Bool, limit: Int?) throws -> [ShazamTag] {
        let order = ascending ? "ASC" : "DESC"
        let sql = """
            SELECT t.Z_PK AS pk, t.ZDATE AS date, t.ZTRACKNAME AS title,
              (SELECT a.ZNAME FROM ZSHARTISTMO a WHERE a.ZTAGRESULT = t.Z_PK ORDER BY a.Z_PK LIMIT 1) AS artist,
              (SELECT m.ZVALUE FROM ZSHMETADATAMO m WHERE m.ZTAGRESULT = t.Z_PK AND m.ZKEY = 'Album'
                 ORDER BY m.Z_PK LIMIT 1) AS album
            FROM ZSHTAGRESULTMO t
            WHERE \(filter) AND t.ZTRACKNAME IS NOT NULL AND t.ZTRACKNAME <> ''
              AND EXISTS (SELECT 1 FROM ZSHARTISTMO a WHERE a.ZTAGRESULT = t.Z_PK AND a.ZNAME <> '')
            ORDER BY t.ZDATE \(order), t.Z_PK \(order)
            \(limit.map { "LIMIT \($0)" } ?? "")
            """
        return try db.query(sql, bindings).compactMap { row in
            guard let pk = row.int("pk"), let seconds = row.double("date"),
                  let title = row.string("title"), let artist = row.string("artist") else { return nil }
            let album = row.string("album").flatMap { $0.isEmpty ? nil : $0 }
            return ShazamTag(pk: pk, date: Date(timeIntervalSinceReferenceDate: seconds),
                             track: Track(artist: artist, title: title, album: album))
        }
    }
}
