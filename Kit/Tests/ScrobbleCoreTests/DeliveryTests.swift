import Foundation
import Testing
import TestSupport
@testable import ScrobbleCore

@Suite struct DeliveryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let a = AccountID(rawValue: "a")
    let b = AccountID(rawValue: "b")

    func tag(_ pk: Int64, _ title: String, at s: TimeInterval) -> ShazamTag {
        ShazamTag(pk: pk, date: t0 + s, track: Track(artist: "Artist", title: title))
    }

    func setup(_ rows: [(ShazamTag, AccountID, DeliveryState)], now: TimeInterval = 1000)
        throws -> (StateStore, Delivery, ManualTimeSource) {
        let store = try StateStore(url: nil)
        try store.apply(rows.map { Transition(key: $0.0.key, tag: $0.0, account: $0.1, to: $0.2) }, now: t0)
        let time = ManualTimeSource(t0 + now)
        return (store, Delivery(store: store, time: time, random: { 0.5 }), time)
    }

    func state(_ store: StateStore, _ tag: ShazamTag, _ account: AccountID) throws -> DeliveryState? {
        try store.states(for: [tag.key])[tag.key]?[account]
    }

    @Test func sendsWaitingOldestFirstInBatches() async throws {   // #18
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100), z = tag(3, "Z", at: 200)
        let (store, delivery, _) = try setup([(z, a, .waiting), (x, a, .waiting), (y, a, .waiting)])
        let fake = FakeScrobbler(maxBatchSize: 2)
        let report = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(await fake.batches.map { $0.map(\.track.title) } == [["X", "Y"], ["Z"]])
        #expect(report.scrobbled == 3)
        #expect(try state(store, z, a) == .scrobbled(at: t0 + 1000))
    }

    @Test func ignoredAndDailyLimitResults() async throws {
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        let (store, delivery, _) = try setup([(x, a, .waiting), (y, a, .waiting)])
        let fake = FakeScrobbler()
        await fake.setReplies([.success([.ignored("Track was ignored"), .dailyLimit])])
        _ = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(try state(store, x, a) == .ignored("Track was ignored"))
        #expect(try state(store, y, a) == .retry(attempt: 1, nextAt: Backoff.nextUTCMidnight(after: t0 + 1000)))
    }

    @Test func tooOldIsIgnoredWithoutARequest() async throws {
        let old = tag(1, "Old", at: 0)
        let (store, delivery, _) = try setup([(old, a, .waiting)], now: 15 * 86_400)
        let fake = FakeScrobbler(maxScrobbleAge: 14 * 86_400)
        _ = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(await fake.batches.isEmpty)
        #expect(try state(store, old, a) == .ignored("Too old for this service (over 14 days)"))
    }

    @Test func accountProblemHoldsOnlyThatAccount() async throws {
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        let (store, delivery, _) = try setup([(x, a, .waiting), (y, a, .waiting), (x, b, .waiting)])
        let failing = FakeScrobbler(), fine = FakeScrobbler()
        await failing.setReplies([.failure(.keyUnusable(code: 26))])
        let report = await delivery.run(scrobblers: [a: failing, b: fine], nowPlaying: [], paused: false)
        #expect(report.problems == [a: .keyUnusable])
        #expect(try state(store, y, a) == .held(.keyUnusable))
        #expect(try state(store, x, b) == .scrobbled(at: t0 + 1000))
        let again = await delivery.run(scrobblers: [a: failing, b: fine], nowPlaying: [], paused: false)
        #expect(again.problems == [a: .keyUnusable])
        #expect(await failing.batches.count == 1)
    }

    @Test func transientErrorSchedulesRetryAndStopsAccount() async throws {
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        let (store, delivery, time) = try setup([(x, a, .waiting), (y, a, .waiting)])
        let fake = FakeScrobbler(maxBatchSize: 1)
        await fake.setReplies([.failure(.transient("offline"))])
        let report = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(await fake.batches.count == 1)
        #expect(try state(store, x, a) == .retry(attempt: 1, nextAt: t0 + 1060))
        #expect(report.nextWake == t0 + 1060)
        time.advance(by: 61)
        _ = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(try state(store, x, a) == .scrobbled(at: t0 + 1061))
    }

    @Test func rateLimitUsesServerDelay() async throws {
        let x = tag(1, "X", at: 0)
        let (store, delivery, _) = try setup([(x, a, .waiting)])
        let fake = FakeScrobbler()
        await fake.setReplies([.failure(.rateLimited(retryAfter: 7))])
        _ = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(try state(store, x, a) == .retry(attempt: 1, nextAt: t0 + 1007))
    }

    @Test func permanentBatchErrorIsolatesTheBadItem() async throws {
        let x = tag(1, "X", at: 0), y = tag(2, "Y", at: 100)
        let (store, delivery, _) = try setup([(x, a, .waiting), (y, a, .waiting)])
        let fake = FakeScrobbler()
        await fake.setReplies([.failure(.permanent("bad")), .success(nil), .failure(.permanent("bad Y"))])
        _ = await delivery.run(scrobblers: [a: fake], nowPlaying: [], paused: false)
        #expect(try state(store, x, a) == .scrobbled(at: t0 + 1000))
        #expect(try state(store, y, a) == .ignored("bad Y"))
    }

    @Test func pausedSendsNothing() async throws {
        let x = tag(1, "X", at: 0)
        let (_, delivery, _) = try setup([(x, a, .waiting)])
        let fake = FakeScrobbler()
        _ = await delivery.run(scrobblers: [a: fake],
                               nowPlaying: [NowPlayingRequest(account: a, tag: x, isRefresh: false)], paused: true)
        #expect(await fake.batches.isEmpty)
        #expect(await fake.nowPlayingTracks.isEmpty)
    }

    @Test func nowPlayingChecksOtherPlayerExcludingOurLastTrack() async throws {   // #22, Review Focus 1
        let previous = tag(1, "Previous", at: 0), current = tag(2, "Current", at: 300)
        let (store, delivery, _) = try setup([(previous, a, .scrobbled(at: t0 + 50)),
                                               (current, a, .nowPlaying(deadline: t0 + 345))], now: 310)
        try store.setNowPlaying(NowPlayingRecord(key: previous.key, sentAt: t0 + 1), for: a)
        let fake = FakeScrobbler()
        _ = await delivery.run(scrobblers: [a: fake],
                               nowPlaying: [NowPlayingRequest(account: a, tag: current, isRefresh: false)], paused: false)
        #expect(await fake.otherPlayerChecks == [previous.track])
        #expect(await fake.nowPlayingTracks == [current.track])
        #expect(try store.lastNowPlaying()[a] == NowPlayingRecord(key: current.key, sentAt: t0 + 310))
    }

    @Test func otherPlayerSkipsTheTag() async throws {
        let current = tag(1, "Current", at: 0)
        let (store, delivery, _) = try setup([(current, a, .nowPlaying(deadline: t0 + 45))], now: 10)
        let fake = FakeScrobbler()
        await fake.setOtherPlayerActive(true)
        _ = await delivery.run(scrobblers: [a: fake],
                               nowPlaying: [NowPlayingRequest(account: a, tag: current, isRefresh: false)], paused: false)
        #expect(await fake.nowPlayingTracks.isEmpty)
        #expect(try state(store, current, a) == .skipped(.otherPlayer))
    }

    @Test func refreshDoesNotCheckOtherPlayer() async throws {
        let current = tag(1, "Current", at: 0)
        let (_, delivery, _) = try setup([(current, a, .scrobbled(at: t0 + 50))], now: 250)
        let fake = FakeScrobbler()
        await fake.setOtherPlayerActive(true)
        _ = await delivery.run(scrobblers: [a: fake],
                               nowPlaying: [NowPlayingRequest(account: a, tag: current, isRefresh: true)], paused: false)
        #expect(await fake.otherPlayerChecks.isEmpty)
        #expect(await fake.nowPlayingTracks == [current.track])
    }
}
