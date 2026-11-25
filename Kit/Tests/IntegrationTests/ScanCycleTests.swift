import Foundation
import Testing
@testable import ScrobbleCore
@testable import ShazamLibrary
import TestSupport

@Suite(.serialized) struct ScanCycleTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let accountID = AccountID(rawValue: "acc")

    func account(addedAt: Date) -> Account {
        Account(id: accountID, preset: .listenbrainz, username: "u", apiURL: URL(string: "https://example.invalid")!,
                webAuthURL: nil, keyMode: .own, addedAt: addedAt)
    }

    @Test func tagIsNowPlayingThenScrobbledOnce() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "Digital Love", artists: ["Daft Punk"], album: "Discovery", date: t0 + 5)
        let time = ManualTimeSource(t0 + 10)
        let store = try StateStore(url: nil)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time, random: { 0.5 }), time: time)
        let fake = FakeScrobbler()
        let acc = account(addedAt: t0)

        let first = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(first.libraryStatus == .ok)
        #expect(first.nowPlaying?.deadline == t0 + 50)
        #expect(await fake.nowPlayingTracks.map(\.title) == ["Digital Love"])
        #expect(first.nextWake == t0 + 50)

        time.advance(by: 41)
        let second = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.map { $0.map(\.track.title) } == [["Digital Love"]])
        #expect(second.nowPlaying == nil)
        #expect(second.waitingCount == 0)

        _ = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.count == 1)
    }

    @Test func restartDuringWindowScrobblesExactlyOnce() async throws {   // Review Focus 4
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "Song", artists: ["A"], album: nil, date: t0 + 5)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let acc = account(addedAt: t0)
        let time = ManualTimeSource(t0 + 10)

        do {
            let store = try StateStore(url: url)
            let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                                  delivery: Delivery(store: store, time: time), time: time)
            let first = await cycle.run(accounts: [acc], scrobblers: [accountID: FakeScrobbler()], settings: EngineSettings())
            #expect(first.nowPlaying != nil)
        }

        time.advance(by: 600)
        let store = try StateStore(url: url)
        let pk = try #require(ShazamLibrary(containerURL: fixture.container).read(since: t0, recentLimit: 5).recent.first)
        guard case .nowPlaying = try store.states(for: [pk.key])[pk.key]?[accountID] else {
            Issue.record("expected persisted .nowPlaying after reopen"); return
        }
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time)
        let fake = FakeScrobbler()
        _ = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        _ = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.map { $0.map(\.track.title) } == [["Song"]])
    }

    @Test func newAccountDoesNotSendHistory() async throws {   // #25
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        for i in 0..<5 { try fixture.addTag(title: "Old \(i)", artists: ["A"], album: nil, date: t0 - Double(1000 * (i + 1))) }
        let time = ManualTimeSource(t0)
        let store = try StateStore(url: nil)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time)
        let fake = FakeScrobbler()
        let snapshot = await cycle.run(accounts: [account(addedAt: t0)], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.isEmpty)
        #expect(snapshot.recent.count == 5)
    }

    @Test func retagAfterCursorOfPreCursorPlayIsDuplicate() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "Song", artists: ["A"], album: nil, date: t0 - 100)
        try fixture.addTag(title: "Song", artists: ["A"], album: nil, date: t0 + 30)
        let time = ManualTimeSource(t0 + 100)
        let store = try StateStore(url: nil)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time)
        let fake = FakeScrobbler()
        let acc = account(addedAt: t0)
        _ = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        time.advance(by: 600)
        _ = await cycle.run(accounts: [acc], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.isEmpty)
        #expect(await fake.nowPlayingTracks.isEmpty)
    }

    @Test func accessDeniedStillDeliversQueuedItems() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase(wal: false)
        try fixture.addTag(title: "Queued", artists: ["A"], album: nil, date: t0 - 300)
        let time = ManualTimeSource(t0)
        let store = try StateStore(url: nil)
        let queued = ShazamTag(pk: 1, date: t0 - 300, track: Track(artist: "A", title: "Queued"))
        try store.apply([Transition(key: queued.key, tag: queued, account: accountID, to: .waiting)], now: t0)
        chmod(fixture.dbURL.path, 0); defer { chmod(fixture.dbURL.path, 0o644) }
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time)
        let fake = FakeScrobbler()
        let snapshot = await cycle.run(accounts: [account(addedAt: t0 - 1000)], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(snapshot.libraryStatus == .accessDenied)
        #expect(await fake.batches.count == 1)
    }

    @Test func nowPlayingSurvivesAutoShazamRetag() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "Song", artists: ["A"], album: nil, date: t0 + 5)
        try fixture.addTag(title: "Song", artists: ["A"], album: nil, date: t0 + 35)
        let time = ManualTimeSource(t0 + 40)
        let store = try StateStore(url: nil)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time, random: { 0.5 }), time: time)
        let snapshot = await cycle.run(accounts: [account(addedAt: t0)], scrobblers: [accountID: FakeScrobbler()], settings: EngineSettings())
        #expect(snapshot.nowPlaying?.tag.pk == 1)
        #expect(snapshot.nowPlaying?.deadline == t0 + 50)
    }

    struct Boom: Error {}

    @Test func failedStatesReadSkipsEngineButStillDelivers() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "New", artists: ["A"], album: nil, date: t0 + 5)
        let time = ManualTimeSource(t0 + 100)
        let store = try StateStore(url: nil)
        let queued = ShazamTag(pk: 99, date: t0 - 300, track: Track(artist: "Q", title: "Queued"))
        try store.apply([Transition(key: queued.key, tag: queued, account: accountID, to: .waiting)], now: t0)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time,
                              statesReader: { _, _ in throw Boom() })
        let fake = FakeScrobbler()
        let snapshot = await cycle.run(accounts: [account(addedAt: t0)], scrobblers: [accountID: fake], settings: EngineSettings())
        #expect(await fake.batches.map { $0.map(\.track.title) } == [["Queued"]])
        #expect(await fake.nowPlayingTracks.isEmpty)
        #expect(snapshot.recent.count == 1)
        let newTag = try #require(snapshot.recent.first)
        #expect(try store.states(for: [newTag.key])[newTag.key] == nil)
    }

    @Test func heldAccountDoesNotPinTheReadWindowForOthers() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        try fixture.addTag(title: "New", artists: ["A"], album: nil, date: t0 + 100)
        let time = ManualTimeSource(t0 + 110)
        let store = try StateStore(url: nil)
        let heldID = AccountID(rawValue: "held"), okID = AccountID(rawValue: "ok")
        func acct(_ id: AccountID) -> Account {
            Account(id: id, preset: .listenbrainz, username: "u", apiURL: URL(string: "https://example.invalid")!,
                    webAuthURL: nil, keyMode: .own, addedAt: t0 - 100_000)
        }
        // A held row far older than everything, which would pin the minimum cursor.
        let old = ShazamTag(pk: 900, date: t0 - 50_000, track: Track(artist: "Old", title: "Old"))
        try store.apply([Transition(key: old.key, tag: old, account: heldID, to: .waiting)], now: t0)
        try store.hold(account: heldID, problem: .signedOut, now: t0)
        try store.setCursor(t0 - 100_000, for: heldID)
        let cycle = ScanCycle(source: ShazamLibrary(containerURL: fixture.container), store: store,
                              delivery: Delivery(store: store, time: time), time: time)
        let snapshot = await cycle.run(accounts: [acct(heldID), acct(okID)],
                                       scrobblers: [heldID: FakeScrobbler(), okID: FakeScrobbler()],
                                       settings: EngineSettings())
        let key = try #require(snapshot.recent.first).key
        #expect(snapshot.states[key]?[okID] != nil)
        #expect(snapshot.states[key]?[heldID] == nil)
        #expect(try store.cursor(for: heldID) == t0 - 100_000)
    }

    @Test func stuckAccountDoesNotStarveOthers() async throws {
        let fixture = try ShazamFixture(); defer { fixture.remove() }
        try fixture.createDatabase()
        // 8 tags after A's open row, more than the injected cap of 5, then B's new tag.
        for i in 0..<8 { try fixture.addTag(title: "Mid \(i)", artists: ["A"], album: nil, date: t0 - 800 + Double(i) * 50) }
        try fixture.addTag(title: "New", artists: ["A"], album: nil, date: t0 + 100)
        let time = ManualTimeSource(t0 + 110)
        let store = try StateStore(url: nil)
        let stuckID = AccountID(rawValue: "stuck"), okID = AccountID(rawValue: "ok")
        func acct(_ id: AccountID) -> Account {
            Account(id: id, preset: .listenbrainz, username: "u", apiURL: URL(string: "https://example.invalid")!,
                    webAuthURL: nil, keyMode: .own, addedAt: t0 - 100_000)
        }
        let old = ShazamTag(pk: 900, date: t0 - 900, track: Track(artist: "Old", title: "Old"))
        try store.apply([Transition(key: old.key, tag: old, account: stuckID, to: .retry(attempt: 9, nextAt: t0 + 100_000))], now: t0)
        try store.setCursor(t0 - 1000, for: stuckID)
        try store.setCursor(t0, for: okID)
        let library = ShazamLibrary(containerURL: fixture.container, tagsSinceLimit: 5)
        let cycle = ScanCycle(source: library, store: store, delivery: Delivery(store: store, time: time, random: { 0.5 }), time: time)
        let okFake = FakeScrobbler()
        let snapshot = await cycle.run(accounts: [acct(stuckID), acct(okID)],
                                       scrobblers: [stuckID: FakeScrobbler(), okID: okFake], settings: EngineSettings())
        let key = try #require(snapshot.recent.first).key
        #expect(snapshot.recent.first?.track.title == "New")
        guard case .nowPlaying = snapshot.states[key]?[okID] else {
            Issue.record("expected nowPlaying for the healthy account, got \(String(describing: snapshot.states[key]?[okID]))"); return
        }
        #expect(await okFake.nowPlayingTracks.map(\.title) == ["New"])
    }

    /// Records every `recentLimit` it is asked for; `recent` is returned only when limit > 0. Windows older than
    /// `unreadableBefore` fail with `.unreadable`.
    final class WindowSource: TagSource, @unchecked Sendable {
        let newest: ShazamTag
        let unreadableBefore: Date?
        private let lock = NSLock()
        private var _limits: [Int] = []
        var limits: [Int] { lock.lock(); defer { lock.unlock() }; return _limits }
        init(newest: ShazamTag, unreadableBefore: Date? = nil) { self.newest = newest; self.unreadableBefore = unreadableBefore }
        func read(since: Date, recentLimit: Int) -> TagSourceResult {
            lock.lock(); _limits.append(recentLimit); lock.unlock()
            if let unreadableBefore, since < unreadableBefore { return TagSourceResult(status: .unreadable("boom")) }
            return TagSourceResult(status: .ok, tagsSince: [], recent: recentLimit > 0 ? [newest] : [])
        }
        func tags(withPKs pks: [Int64]) throws -> [Int64: ShazamTag] { [:] }
    }

    func twoAccounts() -> (old: Account, new: Account) {
        func acct(_ id: String, _ addedAt: Date) -> Account {
            Account(id: AccountID(rawValue: id), preset: .listenbrainz, username: "u", apiURL: URL(string: "https://example.invalid")!,
                    webAuthURL: nil, keyMode: .own, addedAt: addedAt)
        }
        return (acct("old", t0 - 5000), acct("new", t0))
    }

    @Test func recentComesFromTheNewestWindowOnly() async throws {
        let time = ManualTimeSource(t0 + 10)
        let store = try StateStore(url: nil)
        let (oldAcc, newAcc) = twoAccounts()
        try store.setCursor(t0 - 5000, for: oldAcc.id)
        try store.setCursor(t0, for: newAcc.id)
        let newest = ShazamTag(pk: 7, date: t0 + 5, track: Track(artist: "A", title: "OnlyInNewest"))
        let source = WindowSource(newest: newest)
        let cycle = ScanCycle(source: source, store: store, delivery: Delivery(store: store, time: time), time: time)
        let snapshot = await cycle.run(accounts: [oldAcc, newAcc],
                                       scrobblers: [oldAcc.id: FakeScrobbler(), newAcc.id: FakeScrobbler()], settings: EngineSettings())
        #expect(source.limits == [0, 20])   // oldest window first, only the newest asks for recent
        #expect(snapshot.recent == [newest])
    }

    @Test func failedOlderWindowIsNotHiddenByOkNewestWindow() async throws {
        let time = ManualTimeSource(t0 + 10)
        let store = try StateStore(url: nil)
        let (oldAcc, newAcc) = twoAccounts()
        try store.setCursor(t0 - 5000, for: oldAcc.id)
        try store.setCursor(t0, for: newAcc.id)
        let newest = ShazamTag(pk: 7, date: t0 + 5, track: Track(artist: "A", title: "New"))
        let source = WindowSource(newest: newest, unreadableBefore: t0 - 1000)
        let cycle = ScanCycle(source: source, store: store, delivery: Delivery(store: store, time: time), time: time)
        let fake = FakeScrobbler()
        let snapshot = await cycle.run(accounts: [oldAcc, newAcc],
                                       scrobblers: [oldAcc.id: FakeScrobbler(), newAcc.id: fake], settings: EngineSettings())
        #expect(snapshot.libraryStatus == .unreadable("boom"))
        #expect(await fake.nowPlayingTracks.isEmpty)   // engine skipped
        #expect(try store.states(for: [newest.key])[newest.key] == nil)
    }
}
