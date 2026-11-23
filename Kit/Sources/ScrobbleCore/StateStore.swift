import Foundation
import SQLiteLite

public struct PendingItem: Sendable, Equatable {
    public var key: TagKey
    public var track: Track
    public var date: Date
    public var state: DeliveryState
}

public enum UserChoice: String, Sendable {
    case exclude
    case force
}

/// The app's own database (spec §4). Replaces 1.x `lastScrobble` / `notToScrobble`.
public final class StateStore: @unchecked Sendable {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShazamScrobbler/state.sqlite")
    }

    private let db: SQLiteDatabase
    /// Serializes all access: the store is shared by several actors and transactions span calls.
    private let lock = NSRecursiveLock()

    public init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(path: url.path, mode: .readWriteCreate)
            try db.execute("PRAGMA journal_mode=WAL")
        } else {
            db = try SQLiteDatabase(path: "", mode: .inMemory)
        }
        try migrate()
    }

    private func migrate() throws {
        try db.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        let version = try meta("schema_version").flatMap(Int.init) ?? 0
        if version < 1 {
            try db.transaction {
                try db.execute("""
                    CREATE TABLE tags(key TEXT PRIMARY KEY, pk INTEGER, date REAL NOT NULL,
                                      artist TEXT NOT NULL, title TEXT NOT NULL, album TEXT);
                    CREATE INDEX tags_date ON tags(date);
                    CREATE TABLE deliveries(tag_key TEXT NOT NULL, account TEXT NOT NULL, kind TEXT NOT NULL,
                                            next_at REAL, state TEXT NOT NULL, updated REAL NOT NULL,
                                            PRIMARY KEY(tag_key, account));
                    CREATE INDEX deliveries_account_kind ON deliveries(account, kind);
                    CREATE TABLE user_choices(tag_key TEXT PRIMARY KEY, choice TEXT NOT NULL);
                    CREATE TABLE cursors(account TEXT PRIMARY KEY, since REAL NOT NULL);
                    CREATE TABLE now_playing(account TEXT PRIMARY KEY, tag_key TEXT NOT NULL, sent_at REAL NOT NULL);
                    """)
                try setMeta("schema_version", "1")
            }
        }
    }

    // MARK: meta

    public func meta(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]).first?.string("value")
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        lock.lock(); defer { lock.unlock() }
        if let value {
            try db.query("INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)", [.text(key), .text(value)])
        } else {
            try db.query("DELETE FROM meta WHERE key = ?", [.text(key)])
        }
    }

    // MARK: tags and states

    public func record(_ tags: [ShazamTag]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !tags.isEmpty else { return }
        try db.transaction { for tag in tags { try insert(tag) } }
    }

    private func insert(_ tag: ShazamTag) throws {
        try db.query("INSERT OR IGNORE INTO tags(key, pk, date, artist, title, album) VALUES(?,?,?,?,?,?)", [
            .text(tag.key.rawValue), .integer(tag.pk), .real(tag.date.timeIntervalSince1970),
            .text(tag.track.artist), .text(tag.track.title), tag.track.album.map(SQLiteValue.text) ?? .null,
        ])
    }

    public func apply(_ transitions: [Transition], now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        guard !transitions.isEmpty else { return }
        try db.transaction {
            for t in transitions {
                try insert(t.tag)
                try write(t.to, key: t.key, account: t.account, now: now)
            }
        }
    }

    public func set(_ state: DeliveryState, key: TagKey, account: AccountID, now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        try write(state, key: key, account: account, now: now)
    }

    private func write(_ state: DeliveryState, key: TagKey, account: AccountID, now: Date) throws {
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try db.query("""
            INSERT OR REPLACE INTO deliveries(tag_key, account, kind, next_at, state, updated) VALUES(?,?,?,?,?,?)
            """, [.text(key.rawValue), .text(account.rawValue), .text(state.kind),
                  state.retryAt.map { .real($0.timeIntervalSince1970) } ?? .null, .text(json),
                  .real(now.timeIntervalSince1970)])
    }

    public func states(since: Date) throws -> [TagKey: [AccountID: DeliveryState]] {
        lock.lock(); defer { lock.unlock() }
        return try collect(db.query("""
            SELECT d.tag_key, d.account, d.state FROM deliveries d JOIN tags t ON t.key = d.tag_key WHERE t.date > ?
            """, [.real(since.timeIntervalSince1970)]))
    }

    public func states(for keys: [TagKey]) throws -> [TagKey: [AccountID: DeliveryState]] {
        lock.lock(); defer { lock.unlock() }
        guard !keys.isEmpty else { return [:] }
        let marks = Array(repeating: "?", count: keys.count).joined(separator: ",")
        return try collect(db.query("SELECT tag_key, account, state FROM deliveries WHERE tag_key IN (\(marks))",
                                    keys.map { .text($0.rawValue) }))
    }

    private func collect(_ rows: [SQLiteRow]) throws -> [TagKey: [AccountID: DeliveryState]] {
        var result: [TagKey: [AccountID: DeliveryState]] = [:]
        let decoder = JSONDecoder()
        for row in rows {
            guard let key = row.string("tag_key"), let account = row.string("account"),
                  let json = row.string("state") else { continue }
            result[TagKey(rawValue: key), default: [:]][AccountID(rawValue: account)] =
                try decoder.decode(DeliveryState.self, from: Data(json.utf8))
        }
        return result
    }

    public func track(for key: TagKey) throws -> Track? {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT artist, title, album FROM tags WHERE key = ?", [.text(key.rawValue)]).first.flatMap { row in
            guard let artist = row.string("artist"), let title = row.string("title") else { return nil }
            return Track(artist: artist, title: title, album: row.string("album"))
        }
    }

    // MARK: delivery queries

    public func pending(account: AccountID, dueBy now: Date, limit: Int) throws -> [PendingItem] {
        lock.lock(); defer { lock.unlock() }
        let decoder = JSONDecoder()
        return try db.query("""
            SELECT d.tag_key, d.state, t.date, t.artist, t.title, t.album
            FROM deliveries d JOIN tags t ON t.key = d.tag_key
            WHERE d.account = ? AND (d.kind = 'waiting' OR (d.kind = 'retry' AND d.next_at <= ?))
            ORDER BY t.date ASC LIMIT ?
            """, [.text(account.rawValue), .real(now.timeIntervalSince1970), .integer(Int64(limit))]).compactMap { row in
            guard let key = row.string("tag_key"), let json = row.string("state"), let date = row.double("date"),
                  let artist = row.string("artist"), let title = row.string("title") else { return nil }
            return PendingItem(key: TagKey(rawValue: key), track: Track(artist: artist, title: title, album: row.string("album")),
                               date: Date(timeIntervalSince1970: date),
                               state: try decoder.decode(DeliveryState.self, from: Data(json.utf8)))
        }
    }

    /// Earliest retry time among the given accounts' rows only.
    public func nextRetryDate(accounts: [AccountID]) throws -> Date? {
        guard !accounts.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        let marks = accounts.map { _ in "?" }.joined(separator: ",")
        return try db.query("SELECT MIN(next_at) AS n FROM deliveries WHERE kind = 'retry' AND account IN (\(marks))",
                            accounts.map { .text($0.rawValue) }).first?.double("n")
            .map(Date.init(timeIntervalSince1970:))
    }

    /// Compare-and-set: writes `state` only if the row still exists and its current kind is in `fromKinds`.
    /// Used for writes after an await, so a removed account or a user action taken meanwhile is not overwritten.
    @discardableResult
    public func transition(key: TagKey, account: AccountID, fromKinds: Set<String>, to state: DeliveryState,
                           now: Date) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        let kinds = fromKinds.sorted()
        let marks = kinds.map { _ in "?" }.joined(separator: ",")
        let current = try db.query("SELECT kind FROM deliveries WHERE tag_key = ? AND account = ? AND kind IN (\(marks))",
                                   [.text(key.rawValue), .text(account.rawValue)] + kinds.map { .text($0) })
        guard !current.isEmpty else { return false }
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try db.query("""
            UPDATE deliveries SET kind = ?, next_at = ?, state = ?, updated = ?
            WHERE tag_key = ? AND account = ? AND kind IN (\(marks))
            """, [.text(state.kind), state.retryAt.map { .real($0.timeIntervalSince1970) } ?? .null, .text(json),
                  .real(now.timeIntervalSince1970), .text(key.rawValue), .text(account.rawValue)] + kinds.map { .text($0) })
        return true
    }

    /// Derived from held rows only. An account problem with nothing queued is not persisted;
    /// Delivery re-detects it and reports it on each run.
    public func heldProblems() throws -> [AccountID: AccountProblem] {
        lock.lock(); defer { lock.unlock() }
        var result: [AccountID: AccountProblem] = [:]
        for row in try db.query("SELECT account, state FROM deliveries WHERE kind = 'held' GROUP BY account") {
            guard let account = row.string("account"), let json = row.string("state"),
                  case let .held(problem) = try JSONDecoder().decode(DeliveryState.self, from: Data(json.utf8)) else { continue }
            result[AccountID(rawValue: account)] = problem
        }
        return result
    }

    /// Marks the account's waiting/retry rows as held. A no-op when nothing is queued: the problem
    /// is then not remembered here (see `heldProblems()`); Delivery reports it again on each run.
    public func hold(account: AccountID, problem: AccountProblem, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try rewrite(account: account, kinds: ["waiting", "retry"], to: .held(problem), now: now)
    }

    public func releaseHeld(account: AccountID, now: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try rewrite(account: account, kinds: ["held"], to: .waiting, now: now)
    }

    private func rewrite(account: AccountID, kinds: [String], to state: DeliveryState, now: Date) throws {
        let marks = kinds.map { _ in "?" }.joined(separator: ",")
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try db.query("""
            UPDATE deliveries SET kind = ?, next_at = NULL, state = ?, updated = ? WHERE account = ? AND kind IN (\(marks))
            """, [.text(state.kind), .text(json), .real(now.timeIntervalSince1970), .text(account.rawValue)] + kinds.map { .text($0) })
    }

    public func waitingCount() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return Int(try db.query("""
            SELECT COUNT(DISTINCT tag_key) AS c FROM deliveries WHERE kind IN ('waiting', 'retry', 'held')
            """).first?.int("c") ?? 0)
    }

    /// "Skip N Waiting" (#28): skips everything not yet sent and remembers it as excluded,
    /// so the engine doesn't revive it.
    @discardableResult
    public func skipAllWaiting(now: Date) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try db.transaction {
            let keys = try db.query("""
                SELECT DISTINCT tag_key FROM deliveries WHERE kind IN ('waiting', 'retry', 'held')
                """).compactMap { $0.string("tag_key") }
            let json = String(decoding: try JSONEncoder().encode(DeliveryState.skipped(.user)), as: UTF8.self)
            for key in keys {
                try db.query("""
                    UPDATE deliveries SET kind = 'skipped', next_at = NULL, state = ?, updated = ?
                    WHERE tag_key = ? AND kind IN ('waiting', 'retry', 'held')
                    """, [.text(json), .real(now.timeIntervalSince1970), .text(key)])
                try db.query("INSERT OR REPLACE INTO user_choices(tag_key, choice) VALUES(?, 'exclude')", [.text(key)])
            }
            return keys.count
        }
    }

    // MARK: user choices

    public func setChoice(_ choice: UserChoice?, for key: TagKey) throws {
        lock.lock(); defer { lock.unlock() }
        if let choice {
            try db.query("INSERT OR REPLACE INTO user_choices(tag_key, choice) VALUES(?, ?)",
                         [.text(key.rawValue), .text(choice.rawValue)])
        } else {
            try db.query("DELETE FROM user_choices WHERE tag_key = ?", [.text(key.rawValue)])
        }
    }

    public func choices() throws -> (excluded: Set<TagKey>, forced: Set<TagKey>) {
        lock.lock(); defer { lock.unlock() }
        var excluded = Set<TagKey>(), forced = Set<TagKey>()
        for row in try db.query("SELECT tag_key, choice FROM user_choices") {
            guard let key = row.string("tag_key") else { continue }
            if row.string("choice") == UserChoice.exclude.rawValue { excluded.insert(TagKey(rawValue: key)) }
            else { forced.insert(TagKey(rawValue: key)) }
        }
        return (excluded, forced)
    }

    // MARK: cursors

    public func cursor(for account: AccountID) throws -> Date? {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT since FROM cursors WHERE account = ?", [.text(account.rawValue)]).first?.double("since")
            .map(Date.init(timeIntervalSince1970:))
    }

    public func setCursor(_ date: Date, for account: AccountID) throws {
        lock.lock(); defer { lock.unlock() }
        try db.query("INSERT OR REPLACE INTO cursors(account, since) VALUES(?, ?)",
                     [.text(account.rawValue), .real(date.timeIntervalSince1970)])
    }

    /// Moves the cursor forward to just before the oldest unfinished tag (or to the newest
    /// finished one), so scans don't re-read the whole history. Never moves backwards.
    public func advanceCursor(for account: AccountID) throws {
        lock.lock(); defer { lock.unlock() }
        let id = SQLiteValue.text(account.rawValue)
        let oldestOpen = try db.query("""
            SELECT MIN(t.date) AS d FROM deliveries d JOIN tags t ON t.key = d.tag_key
            WHERE d.account = ? AND d.kind IN ('waiting', 'nowPlaying', 'retry', 'held')
            """, [id]).first?.double("d")
        let newestAny = try db.query("""
            SELECT MAX(t.date) AS d FROM deliveries d JOIN tags t ON t.key = d.tag_key WHERE d.account = ?
            """, [id]).first?.double("d")
        guard let target = oldestOpen.map({ $0 - 0.001 }) ?? newestAny else { return }
        let current = try cursor(for: account)?.timeIntervalSince1970 ?? -.infinity
        if target > current { try setCursor(Date(timeIntervalSince1970: target), for: account) }
    }

    // MARK: now playing

    public func lastNowPlaying() throws -> [AccountID: NowPlayingRecord] {
        lock.lock(); defer { lock.unlock() }
        var result: [AccountID: NowPlayingRecord] = [:]
        for row in try db.query("SELECT account, tag_key, sent_at FROM now_playing") {
            guard let account = row.string("account"), let key = row.string("tag_key"),
                  let sentAt = row.double("sent_at") else { continue }
            result[AccountID(rawValue: account)] = NowPlayingRecord(key: TagKey(rawValue: key),
                                                                    sentAt: Date(timeIntervalSince1970: sentAt))
        }
        return result
    }

    public func setNowPlaying(_ record: NowPlayingRecord, for account: AccountID) throws {
        lock.lock(); defer { lock.unlock() }
        try db.query("INSERT OR REPLACE INTO now_playing(account, tag_key, sent_at) VALUES(?,?,?)",
                     [.text(account.rawValue), .text(record.key.rawValue), .real(record.sentAt.timeIntervalSince1970)])
    }

    public func removeAccount(_ account: AccountID) throws {
        lock.lock(); defer { lock.unlock() }
        try db.transaction {
            for table in ["deliveries", "cursors", "now_playing"] {
                try db.query("DELETE FROM \(table) WHERE account = ?", [.text(account.rawValue)])
            }
        }
    }
}

extension DeliveryState {
    var kind: String {
        switch self {
        case .waiting: "waiting"
        case .nowPlaying: "nowPlaying"
        case .scrobbled: "scrobbled"
        case .tooShort: "tooShort"
        case .skipped: "skipped"
        case .ignored: "ignored"
        case .held: "held"
        case .retry: "retry"
        }
    }

    var retryAt: Date? {
        if case let .retry(_, nextAt) = self { return nextAt }
        return nil
    }
}
