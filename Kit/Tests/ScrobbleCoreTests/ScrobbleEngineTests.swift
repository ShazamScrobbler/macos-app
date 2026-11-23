import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct ScrobbleEngineTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let a = AccountID(rawValue: "a")
    let b = AccountID(rawValue: "b")

    func tag(_ pk: Int64, _ title: String, at s: TimeInterval, artist: String = "Artist") -> ShazamTag {
        ShazamTag(pk: pk, date: t0 + s, track: Track(artist: artist, title: title))
    }

    func run(_ tags: [ShazamTag], now s: TimeInterval,
             accounts: [AccountCursor]? = nil,
             states: [TagKey: [AccountID: DeliveryState]] = [:],
             settings: EngineSettings = EngineSettings(),
             excluded: Set<TagKey> = [], forced: Set<TagKey> = [],
             lastNowPlaying: [AccountID: NowPlayingRecord] = [:]) -> EngineOutput {
        ScrobbleEngine.evaluate(EngineInput(
            tags: tags, now: t0 + s, settings: settings,
            accounts: accounts ?? [AccountCursor(id: a, since: t0 - 1)],
            states: states, excluded: excluded, forced: forced, lastNowPlaying: lastNowPlaying))
    }

    func states(_ out: EngineOutput, _ account: AccountID? = nil) -> [String: DeliveryState] {
        let acc = account ?? a
        return Dictionary(out.transitions.filter { $0.account == acc }.map { ($0.tag.track.title, $0.to) },
                          uniquingKeysWith: { _, last in last })
    }

    @Test func accountOnlyGetsTagsAfterItsCursor() {   // #25
        let out = run([tag(1, "Old", at: 0), tag(2, "New", at: 100)], now: 400,
                      accounts: [AccountCursor(id: a, since: t0 + 50)])
        #expect(states(out) == ["New": .waiting])
    }

    @Test func newestInsideWindowIsNowPlayingAndRequestsSend() {
        let out = run([tag(1, "Song", at: 0)], now: 10)
        #expect(states(out) == ["Song": .nowPlaying(deadline: t0 + 45)])
        #expect(out.nowPlaying == [NowPlayingRequest(account: a, tag: tag(1, "Song", at: 0), isRefresh: false)])
        #expect(out.nextWake == t0 + 45)
    }

    @Test func newestPastDeadlineIsWaitingWithoutNowPlaying() {
        let out = run([tag(1, "Song", at: 0)], now: 46)
        #expect(states(out) == ["Song": .waiting])
        #expect(out.nowPlaying.isEmpty)
    }

    @Test func newerTagBeforeDeadlineMakesPreviousTooShort() {   // #16
        let first = tag(1, "First", at: 0)
        let out = run([first, tag(2, "Second", at: 20)], now: 25,
                      states: [first.key: [a: .nowPlaying(deadline: t0 + 45)]])
        #expect(states(out)["First"] == .tooShort)
        #expect(states(out)["Second"] == .nowPlaying(deadline: t0 + 65))
    }

    @Test func previousPlayedLongEnoughIsWaiting() {
        let out = run([tag(1, "First", at: 0), tag(2, "Second", at: 200)], now: 210)
        #expect(states(out)["First"] == .waiting)
    }

    @Test func autoShazamRetagIsDuplicateAndDoesNotShortenOriginal() {   // #42, Review Focus 3
        let out = run([tag(1, "Loop", at: 0), tag(2, "Loop", at: 30), tag(3, "Next", at: 200)], now: 210)
        let rows = out.transitions.filter { $0.account == a }
        #expect(rows.first { $0.tag.pk == 1 }?.to == .waiting)
        #expect(rows.first { $0.tag.pk == 2 }?.to == .skipped(.duplicate))
        #expect(rows.first { $0.tag.pk == 3 }?.to == .nowPlaying(deadline: t0 + 245))
    }

    @Test func pausedIgnoreSkipsNewTags() {   // #17
        let out = run([tag(1, "Song", at: 0)], now: 10, settings: EngineSettings(paused: true, pauseMode: .ignore))
        #expect(states(out) == ["Song": .skipped(.paused)])
        #expect(out.nowPlaying.isEmpty)
    }

    @Test func pausedKeepTracksButSendsNothing() {
        let out = run([tag(1, "Song", at: 0)], now: 10, settings: EngineSettings(paused: true, pauseMode: .keep))
        #expect(states(out) == ["Song": .nowPlaying(deadline: t0 + 45)])
        #expect(out.nowPlaying.isEmpty)
    }

    @Test func excludedIsSkippedButScrobbledStays() {
        let playing = tag(1, "Playing", at: 0)
        let done = tag(0, "Done", at: -300)
        let out = run([done, playing], now: 10,
                      states: [playing.key: [a: .nowPlaying(deadline: t0 + 45)], done.key: [a: .scrobbled(at: t0 - 200)]],
                      excluded: [playing.key, done.key])
        #expect(states(out) == ["Playing": .skipped(.user)])
    }

    @Test func forcedRevivesTooShortAndUnexcludedRevivesUserSkip() {
        let short = tag(1, "Short", at: 0)
        let skipped = tag(2, "Skipped", at: 100)
        let out = run([short, skipped, tag(3, "Now", at: 300)], now: 310,
                      states: [short.key: [a: .tooShort], skipped.key: [a: .skipped(.user)]],
                      forced: [short.key])
        #expect(states(out)["Short"] == .waiting)
        #expect(states(out)["Skipped"] == .waiting)
    }

    @Test func restartAfterDeadlineResolvesPersistedNowPlaying() {   // Review Focus 4
        let song = tag(1, "Song", at: 0)
        let alone = run([song], now: 600, states: [song.key: [a: .nowPlaying(deadline: t0 + 45)]])
        #expect(states(alone) == ["Song": .waiting])
        let withNext = run([song, tag(2, "Next", at: 30)], now: 600, states: [song.key: [a: .nowPlaying(deadline: t0 + 45)]])
        #expect(states(withNext)["Song"] == .tooShort)
    }

    @Test func nowPlayingIsRefreshedEvery240sUntil600s() {   // #47
        let song = tag(1, "Song", at: 0)
        let sentEarly = [a: NowPlayingRecord(key: song.key, sentAt: t0 + 1)]
        let notYet = run([song], now: 100, states: [song.key: [a: .waiting]], lastNowPlaying: sentEarly)
        #expect(notYet.nowPlaying.isEmpty)
        #expect(notYet.nextWake == t0 + 241)
        let due = run([song], now: 242, states: [song.key: [a: .scrobbled(at: t0 + 50)]], lastNowPlaying: sentEarly)
        #expect(due.nowPlaying == [NowPlayingRequest(account: a, tag: song, isRefresh: true)])
        let capped = run([song], now: 601, states: [song.key: [a: .scrobbled(at: t0 + 50)]],
                         lastNowPlaying: [a: NowPlayingRecord(key: song.key, sentAt: t0 + 300)])
        #expect(capped.nowPlaying.isEmpty)
    }

    @Test func deliveryOwnedStatesAreLeftAlone() {
        let w = tag(1, "W", at: 0), r = tag(2, "R", at: 100), h = tag(3, "H", at: 200), i = tag(4, "I", at: 300)
        let out = run([w, r, h, i], now: 1000, states: [
            w.key: [a: .waiting], r.key: [a: .retry(attempt: 2, nextAt: t0 + 2000)],
            h.key: [a: .held(.signedOut)], i.key: [a: .ignored("Track ignored")],
        ])
        #expect(out.transitions.isEmpty)
    }

    @Test func sameSecondDifferentSongsAreDistinctAndSameSongSameSecondIsOneRow() {   // Review Focus 3
        let out = run([tag(1, "A", at: 0), tag(2, "B", at: 0), tag(3, "B", at: 0), tag(4, "C", at: 300)], now: 310)
        let rows = out.transitions.filter { $0.account == a }
        #expect(rows.count == 3)
        #expect(states(out)["A"] == .tooShort)
        #expect(states(out)["B"] == .waiting)
    }

    @Test func accountsAreIndependent() {
        let out = run([tag(1, "Song", at: 0)], now: 10,
                      accounts: [AccountCursor(id: a, since: t0 - 1), AccountCursor(id: b, since: t0 + 5)])
        #expect(states(out, a) == ["Song": .nowPlaying(deadline: t0 + 45)])
        #expect(states(out, b).isEmpty)
    }
}
