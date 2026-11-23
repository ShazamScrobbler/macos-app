import Foundation
import Testing
@testable import ScrobbleCore
import ShazamLibrary
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
}
