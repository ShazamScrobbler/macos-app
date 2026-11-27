import Foundation
import Testing
import SQLiteLite
@testable import ScrobbleCore

@Suite struct StateStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let a = AccountID(rawValue: "a")
    let b = AccountID(rawValue: "b")

    func tag(_ pk: Int64, _ title: String, at s: TimeInterval) -> ShazamTag {
        ShazamTag(pk: pk, date: t0 + s, track: Track(artist: "Artist", title: title, album: "Album"))
    }
    func transition(_ tag: ShazamTag, _ account: AccountID, _ state: DeliveryState) -> Transition {
        Transition(key: tag.key, tag: tag, account: account, to: state)
    }

    @Test func appliesAndReadsStatesPerAccount() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0)
        try s.apply([transition(x, a, .waiting), transition(x, b, .tooShort)], now: t0)
        try s.apply([transition(x, a, .scrobbled(at: t0 + 60))], now: t0 + 60)
        #expect(try s.states(since: t0 - 1)[x.key] == [a: .scrobbled(at: t0 + 60), b: .tooShort])
        #expect(try s.states(since: t0)[x.key] == nil)
        #expect(try s.track(for: x.key) == x.track)
    }

    @Test func pendingReturnsWaitingAndDueRetriesOldestFirst() throws {
        let s = try StateStore(url: nil)
        let old = tag(1, "Old", at: 0), mid = tag(2, "Mid", at: 100), late = tag(3, "Late", at: 200)
        try s.apply([
            transition(late, a, .waiting),
            transition(old, a, .retry(attempt: 1, nextAt: t0 + 500)),
            transition(mid, a, .retry(attempt: 1, nextAt: t0 + 5000)),
            transition(old, b, .waiting),
        ], now: t0)
        let due = try s.pending(account: a, dueBy: t0 + 600, limit: 50)
        #expect(due.map(\.track.title) == ["Old", "Late"])
        #expect(try s.pending(account: a, dueBy: t0 + 600, limit: 1).count == 1)
        #expect(try s.nextRetryDate(accounts: [a]) == t0 + 500)
    }

    @Test func holdAndReleasePerAccount() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        try s.apply([transition(x, a, .waiting), transition(y, a, .retry(attempt: 2, nextAt: t0)), transition(x, b, .waiting)], now: t0)
        try s.hold(account: a, problem: .keyUnusable)
        #expect(try s.heldProblems() == [a: .keyUnusable])
        #expect(try s.pending(account: a, dueBy: t0 + 9999, limit: 50).isEmpty)
        try s.releaseHeld(account: a)
        #expect(try s.heldProblems().isEmpty)
        #expect(try s.pending(account: a, dueBy: t0, limit: 50).count == 2)
    }

    @Test func waitingCountAndSkipAllWaitingAlsoExcludes() throws {   // #28
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100), z = tag(3, "Z", at: 200)
        try s.apply([transition(x, a, .waiting), transition(x, b, .held(.signedOut)),
                     transition(y, a, .retry(attempt: 1, nextAt: t0)), transition(z, a, .scrobbled(at: t0))], now: t0)
        #expect(try s.waitingCount() == 2)
        #expect(try s.skipAllWaiting(now: t0) == 2)
        #expect(try s.waitingCount() == 0)
        #expect(try s.choices().excluded == [x.key, y.key])
        #expect(try s.states(since: t0 - 1)[z.key]?[a] == .scrobbled(at: t0))
    }

    @Test func choicesReplaceEachOther() throws {
        let s = try StateStore(url: nil)
        let k = tag(1, "X", at: 0).key
        try s.setChoice(.exclude, for: k)
        #expect(try s.choices().excluded == [k])
        try s.setChoice(.force, for: k)
        #expect(try s.choices().excluded.isEmpty)
        #expect(try s.choices().forced == [k])
        try s.setChoice(nil, for: k)
        #expect(try s.choices().forced.isEmpty)
    }

    @Test func cursorAdvancesToOldestUnfinishedAndNeverBackwards() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100), z = tag(3, "Z", at: 200)
        try s.setCursor(t0 - 10, for: a)
        try s.apply([transition(x, a, .scrobbled(at: t0)), transition(y, a, .waiting), transition(z, a, .tooShort)], now: t0)
        try s.advanceCursor(for: a)
        #expect(try s.cursor(for: a)! < t0 + 100)
        #expect(try s.cursor(for: a)! > t0)
        try s.apply([transition(y, a, .scrobbled(at: t0 + 300))], now: t0 + 300)
        try s.advanceCursor(for: a)
        #expect(try s.cursor(for: a) == t0 + 200)
    }

    @Test func nowPlayingRecordsAndAccountRemoval() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0)
        try s.apply([transition(x, a, .waiting)], now: t0)
        try s.setCursor(t0, for: a)
        try s.setNowPlaying(NowPlayingRecord(key: x.key, sentAt: t0 + 5), for: a)
        #expect(try s.lastNowPlaying() == [a: NowPlayingRecord(key: x.key, sentAt: t0 + 5)])
        try s.removeAccount(a)
        #expect(try s.lastNowPlaying().isEmpty)
        #expect(try s.cursor(for: a) == nil)
        #expect(try s.states(since: t0 - 1)[x.key] == nil)
    }

    @Test func persistsAcrossReopenAndRecordsSchemaVersion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let x = tag(1, "X", at: 0)
        do {
            let s = try StateStore(url: url)
            try s.apply([transition(x, a, .waiting)], now: t0)
            try s.setMeta("legacy.lastScrobblePK", "11938")
        }
        let reopened = try StateStore(url: url)
        #expect(try reopened.states(since: t0 - 1)[x.key]?[a] == .waiting)
        #expect(try reopened.meta("schema_version") == "2")
        #expect(try reopened.meta("legacy.lastScrobblePK") == "11938")
    }

    @Test func reopeningAVersion1FileMigratesToVersion2() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let x = tag(1, "X", at: 0)
        do {
            let s = try StateStore(url: url)
            try s.apply([transition(x, a, .waiting)], now: t0)
        }
        // Turn it back into a v1 file: no deliveries_kind index, schema_version 1.
        do {
            let raw = try SQLiteDatabase(path: url.path, mode: .readWriteCreate)
            try raw.execute("DROP INDEX deliveries_kind")
            try raw.execute("UPDATE meta SET value = '1' WHERE key = 'schema_version'")
        }
        func indexCount() throws -> Int {
            let raw = try SQLiteDatabase(path: url.path, mode: .readWriteCreate)
            return try raw.query("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'deliveries_kind'").count
        }
        #expect(try indexCount() == 0)
        let migrated = try StateStore(url: url)
        #expect(try migrated.meta("schema_version") == "2")
        #expect(try indexCount() == 1)
        #expect(try migrated.states(since: t0 - 1)[x.key]?[a] == .waiting)
    }

    @Test func advanceCursorUsesNewestRowOfThatAccountOnly() throws {
        let s = try StateStore(url: nil)
        let old = tag(1, "Old", at: 10), newer = tag(2, "Newer", at: 500)
        try s.apply([transition(old, a, .scrobbled(at: t0)), transition(newer, b, .scrobbled(at: t0))], now: t0)
        try s.setCursor(t0, for: a)
        try s.advanceCursor(for: a)
        #expect(try s.cursor(for: a) == t0 + 10)
    }

    @Test func skipAllWaitingIsSetBasedAndCountsDistinctTags() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 10), z = tag(3, "Z", at: 20)
        try s.apply([transition(x, a, .waiting), transition(x, b, .retry(attempt: 1, nextAt: t0 + 60)),
                     transition(y, a, .held(.signedOut)), transition(z, a, .scrobbled(at: t0))], now: t0)
        #expect(try s.skipAllWaiting(now: t0 + 1) == 2)
        let states = try s.states(for: [x.key, y.key, z.key])
        #expect(states[x.key]?[a] == .skipped(.user))
        #expect(states[x.key]?[b] == .skipped(.user))
        #expect(states[y.key]?[a] == .skipped(.user))
        #expect(states[z.key]?[a] == .scrobbled(at: t0))
        #expect(try s.choices().excluded == [x.key, y.key])
        #expect(try s.skipAllWaiting(now: t0 + 2) == 0)
    }

    @Test func survivesConcurrentUse() async throws {
        let s = try StateStore(url: nil)
        let tags = (0..<50).map { tag(Int64($0), "T\($0)", at: TimeInterval($0)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (i, t) in tags.enumerated() {
                group.addTask {
                    try s.apply([transition(t, a, .waiting), transition(t, b, .waiting)], now: t0)
                    switch i % 5 {
                    case 0: try s.setChoice(.force, for: t.key)
                    case 1: _ = try s.skipAllWaiting(now: t0)
                    case 2: try s.setCursor(t0 + Double(i), for: a)
                    case 3: _ = try s.pending(account: a, dueBy: t0, limit: 10)
                    default: try s.advanceCursor(for: b)
                    }
                }
            }
            try await group.waitForAll()
        }
        // No row lost or torn: every tag kept both accounts' states, and each skip excluded
        // exactly what it skipped (a later .force may replace an exclusion).
        let all = try s.states(since: t0 - 1000)
        #expect(all.values.allSatisfy { $0.count == 2 })
        let waiting = try s.waitingCount()
        let choices = try s.choices()
        #expect(waiting + choices.excluded.count + choices.forced.count >= 50)
        #expect(choices.excluded.isDisjoint(with: choices.forced))
        #expect(try s.states(since: t0 - 1000).count == 50)
    }

    @Test func compareAndSetOnlyTransitionsMatchingKinds() throws {
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0)
        try s.apply([transition(x, a, .waiting)], now: t0)
        #expect(try s.transition(key: x.key, account: a, fromKinds: ["nowPlaying"], to: .scrobbled(at: t0), now: t0) == false)
        #expect(try s.states(for: [x.key])[x.key]?[a] == .waiting)
        #expect(try s.transition(key: x.key, account: a, fromKinds: ["waiting", "retry"],
                                 to: .retry(attempt: 1, nextAt: t0 + 60), now: t0) == true)
        #expect(try s.states(for: [x.key])[x.key]?[a] == .retry(attempt: 1, nextAt: t0 + 60))
        #expect(try s.nextRetryDate(accounts: [a]) == t0 + 60)
        #expect(try s.nextRetryDate(accounts: [b]) == nil)
        #expect(try s.transition(key: x.key, account: b, fromKinds: ["waiting", "retry"], to: .waiting, now: t0) == false)
        #expect(try s.states(for: [x.key])[x.key]?[b] == nil)
    }

    // MARK: final fix wave

    @Test func forceMovesSkippedAndTooShortRowsToWaitingAndSetsChoice() throws {   // C1
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        let c = AccountID(rawValue: "c"), d = AccountID(rawValue: "d")
        try s.apply([transition(x, a, .skipped(.user)), transition(x, b, .tooShort),
                     transition(x, c, .scrobbled(at: t0)), transition(x, d, .ignored("bad")),
                     transition(y, a, .skipped(.user))], now: t0)
        try s.setChoice(.exclude, for: x.key)
        try s.advanceCursor(for: a)
        let cursor = try s.cursor(for: a)
        try s.force(key: x.key, now: t0 + 10)
        #expect(try s.choices().forced == [x.key])
        #expect(try s.choices().excluded.isEmpty)
        #expect(try s.states(for: [x.key])[x.key] == [a: .waiting, b: .waiting, c: .scrobbled(at: t0), d: .ignored("bad")])
        #expect(try s.states(for: [y.key])[y.key]?[a] == .skipped(.user))
        #expect(try s.pending(account: a, dueBy: t0 + 10, limit: 50).map(\.key) == [x.key])
        #expect(try s.cursor(for: a) == cursor)
    }

    @Test func makeTransientRetriesDueLeavesDailyLimitRetries() throws {   // I1
        let s = try StateStore(url: nil)
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100), z = tag(3, "Z", at: 200)
        try s.apply([transition(x, a, .retry(attempt: 3, nextAt: t0 + 1800)),
                     transition(y, a, .retryAfterDailyLimit(attempt: 1, nextAt: t0 + 1800)),
                     transition(z, b, .retry(attempt: 1, nextAt: t0 + 5))], now: t0)
        #expect(try s.makeTransientRetriesDue(now: t0 + 10) == 1)
        #expect(try s.states(for: [x.key])[x.key]?[a] == .retry(attempt: 3, nextAt: t0 + 10))
        #expect(try s.states(for: [y.key])[y.key]?[a] == .retryAfterDailyLimit(attempt: 1, nextAt: t0 + 1800))
        #expect(try s.states(for: [z.key])[z.key]?[b] == .retry(attempt: 1, nextAt: t0 + 5))
        #expect(try s.pending(account: a, dueBy: t0 + 10, limit: 50).map(\.key) == [x.key])
        #expect(try s.nextRetryDate(accounts: [a]) == t0 + 10)
    }

    @Test func retryRowsWrittenBeforeTheDailyLimitCaseStillDecode() throws {   // I1: Codable compatibility
        let old = #"{"retry":{"attempt":2,"nextAt":10}}"#
        #expect(try JSONDecoder().decode(DeliveryState.self, from: Data(old.utf8))
                == .retry(attempt: 2, nextAt: Date(timeIntervalSinceReferenceDate: 10)))
        let daily = DeliveryState.retryAfterDailyLimit(attempt: 1, nextAt: t0)
        #expect(try JSONDecoder().decode(DeliveryState.self, from: JSONEncoder().encode(daily)) == daily)
    }
}
