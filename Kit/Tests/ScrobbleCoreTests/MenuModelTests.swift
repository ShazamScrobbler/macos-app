import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct MenuModelTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let lastfm = Account(id: AccountID(rawValue: "1"), preset: .lastfm, username: "steph",
                         apiURL: URL(string: "https://ws.audioscrobbler.com/2.0/")!, webAuthURL: nil, keyMode: .builtIn,
                         addedAt: .distantPast)
    let lb = Account(id: AccountID(rawValue: "2"), preset: .listenbrainz, username: "steph",
                     apiURL: URL(string: "https://api.listenbrainz.org")!, webAuthURL: nil, keyMode: .own,
                     addedAt: .distantPast)

    func tag(_ pk: Int64, _ title: String, at s: TimeInterval) -> ShazamTag {
        ShazamTag(pk: pk, date: t0 + s, track: Track(artist: "A", title: title))
    }

    @Test func aggregateRules() {
        #expect(MenuModel.aggregate([]) == .none)
        #expect(MenuModel.aggregate([.scrobbled(at: t0), .scrobbled(at: t0)]) == .done)
        #expect(MenuModel.aggregate([.scrobbled(at: t0), .retry(attempt: 1, nextAt: t0)]) == .partial)
        #expect(MenuModel.aggregate([.scrobbled(at: t0), .ignored("x")]) == .partial)
        #expect(MenuModel.aggregate([.tooShort, .skipped(.user)]) == .skipped)
        #expect(MenuModel.aggregate([.waiting, .tooShort]) == .pending)
    }

    @Test func nowPlayingIsSeparateAndRecentIsCappedAt20() {
        var snapshot = Snapshot.empty
        snapshot.libraryStatus = .ok
        snapshot.recent = (0..<25).map { tag(Int64(100 - $0), "S\($0)", at: Double(-$0 * 60)) }
        snapshot.nowPlaying = NowPlayingInfo(tag: snapshot.recent[0], deadline: t0 + 45)
        snapshot.states = [snapshot.recent[0].key: [lastfm.id: .nowPlaying(deadline: t0 + 45)],
                           snapshot.recent[1].key: [lastfm.id: .scrobbled(at: t0), lb.id: .waiting]]
        let content = MenuModel.content(snapshot: snapshot, accounts: [lastfm, lb])
        #expect(content.nowPlaying?.row.track.title == "S0")
        #expect(content.recent.count == 20)
        #expect(content.recent.first?.track.title == "S1")
        #expect(content.recent.first?.aggregate == .partial)
        #expect(content.recent.first?.lines.map(\.account.id) == [lastfm.id, lb.id])
        #expect(content.library == nil)
    }

    @Test func problemsAndLibraryNotice() {
        var snapshot = Snapshot.empty
        snapshot.libraryStatus = .accessDenied
        snapshot.problems = [lastfm.id: .keyUnusable, lb.id: .signedOut]
        let content = MenuModel.content(snapshot: snapshot, accounts: [lastfm, lb])
        #expect(content.library == .accessDenied)
        #expect(content.problems == [ProblemRow(account: lastfm, problem: .keyUnusable),
                                     ProblemRow(account: lb, problem: .signedOut)])
        snapshot.libraryStatus = .noLibraryYet
        #expect(MenuModel.content(snapshot: snapshot, accounts: []).library == .waitingForShazam)
    }

    @Test func problemRowsFollowAccountOrder() {
        var snapshot = Snapshot.empty
        snapshot.problems = [lastfm.id: .keyUnusable, lb.id: .signedOut]
        let content = MenuModel.content(snapshot: snapshot, accounts: [lb, lastfm])
        #expect(content.problems.map(\.account) == [lb, lastfm])
    }

    @Test func changedSlotsReportsOnlyDifferences() {
        #expect(MenuModel.changedSlots(old: ["a", "b", nil], new: ["a", "c", "d"]) == [1, 2])
        #expect(MenuModel.changedSlots(old: ["a", "b"], new: ["a"]) == [1])
        #expect(MenuModel.changedSlots(old: [String?](), new: []) == [])
    }

    @Test func countdownFormatting() {
        #expect(MenuModel.countdown(to: t0 + 13, now: t0) == "0:13")
        #expect(MenuModel.countdown(to: t0 + 75.4, now: t0) == "1:16")
        #expect(MenuModel.countdown(to: t0, now: t0 + 5) == "0:00")
    }
}
