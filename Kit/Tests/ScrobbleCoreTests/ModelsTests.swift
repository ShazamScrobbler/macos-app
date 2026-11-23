import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct ModelsTests {
    @Test func tagKeyIgnoresSubSecondsAndAlbum() {
        let d = Date(timeIntervalSince1970: 1_700_000_000.75)
        let a = TagKey(date: d, track: Track(artist: "Air", title: "Kelly", album: "X"))
        let b = TagKey(date: Date(timeIntervalSince1970: 1_700_000_000), track: Track(artist: "Air", title: "Kelly"))
        #expect(a == b)
        #expect(TagKey(rawValue: a.rawValue) == a)
    }

    @Test func matchKeyIsCaseDiacriticAndWhitespaceInsensitive() {
        #expect(Track(artist: " Beyoncé ", title: "HALO").matchKey == Track(artist: "beyonce", title: "halo").matchKey)
        #expect(Track(artist: "A", title: "B").matchKey != Track(artist: "AB", title: "").matchKey)
    }

    @Test func deliveryStateRoundTripsThroughJSON() throws {
        let states: [DeliveryState] = [
            .waiting, .nowPlaying(deadline: Date(timeIntervalSince1970: 5)), .scrobbled(at: Date(timeIntervalSince1970: 6)),
            .tooShort, .skipped(.otherPlayer), .ignored("Track ignored"), .held(.keyUnusable),
            .retry(attempt: 3, nextAt: Date(timeIntervalSince1970: 9)),
        ]
        for s in states {
            let data = try JSONEncoder().encode(s)
            #expect(try JSONDecoder().decode(DeliveryState.self, from: data) == s)
        }
    }

    @Test func finalStates() {
        #expect(DeliveryState.scrobbled(at: .now).isFinal)
        #expect(DeliveryState.tooShort.isFinal)
        #expect(DeliveryState.skipped(.user).isFinal)
        #expect(DeliveryState.ignored("x").isFinal)
        #expect(!DeliveryState.waiting.isFinal)
        #expect(!DeliveryState.held(.signedOut).isFinal)
        #expect(!DeliveryState.retry(attempt: 1, nextAt: .now).isFinal)
        #expect(!DeliveryState.nowPlaying(deadline: .now).isFinal)
    }

    @Test func presetsMapToFamiliesAndDefaults() {
        #expect(ServicePreset.lastfm.family == .audioscrobbler)
        #expect(ServicePreset.customListenBrainz.family == .listenBrainz)
        #expect(ServicePreset.lastfm.defaultAPIURL?.absoluteString == "https://ws.audioscrobbler.com/2.0/")
        #expect(ServicePreset.librefm.defaultWebAuthURL?.absoluteString == "https://libre.fm/api/auth/")
        #expect(ServicePreset.listenbrainz.defaultAPIURL?.absoluteString == "https://api.listenbrainz.org")
        #expect(ServicePreset.customAudioscrobbler.defaultAPIURL == nil)
    }

    @Test func manualTimeSourceAdvances() {
        let t = ManualTimeSource(Date(timeIntervalSince1970: 100))
        t.advance(by: 46)
        #expect(t.now == Date(timeIntervalSince1970: 146))
    }
}
