import Foundation
import Testing
import ScrobbleCore
@testable import ScrobbleClients

@Suite struct AudioscrobblerClientTests {
    let api = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    let t = Date(timeIntervalSince1970: 1_700_000_000)

    func client(_ stub: StubTransport) -> AudioscrobblerClient {
        AudioscrobblerClient(apiURL: api, apiKey: "KEY", apiSecret: "SECRET", sessionKey: "SK", username: "steph", transport: stub)
    }
    func item(_ title: String, album: String? = nil, at offset: TimeInterval = 0) -> ScrobbleItem {
        let track = Track(artist: "Daft Punk", title: title, album: album)
        return ScrobbleItem(key: TagKey(date: t + offset, track: track), track: track, date: t + offset)
    }

    @Test func nowPlayingSendsNoDuration() async throws {   // #47
        let stub = StubTransport([.init(body: #"{"nowplaying":{}}"#)])
        try await client(stub).nowPlaying(Track(artist: "Daft Punk", title: "Digital Love", album: "Discovery"))
        let form = await stub.form(0)
        #expect(form["method"] == "track.updateNowPlaying")
        #expect(form["album"] == "Discovery")
        #expect(form["sk"] == "SK")
        #expect(form["duration"] == nil)
        #expect(form["api_sig"] == AudioscrobblerSignature.sign(form.filter { $0.key != "api_sig" }, secret: "SECRET"))
    }

    @Test func batchSendsIndexedParamsAndMapsIgnored() async throws {   // #18, #31, #37
        let stub = StubTransport([.init(body: """
            {"scrobbles":{"scrobble":[
              {"track":{"#text":"One"},"ignoredMessage":{"code":"0","#text":""}},
              {"track":{"#text":"Two"},"ignoredMessage":{"code":"1","#text":"Artist was ignored"}}],
             "@attr":{"accepted":1,"ignored":1}}}
            """)])
        let results = try await client(stub).scrobble([item("One", album: "Discovery"), item("Two", at: 60)])
        #expect(results == [.accepted, .ignored("Artist was ignored")])
        let form = await stub.form(0)
        #expect(form["track[0]"] == "One")
        #expect(form["album[0]"] == "Discovery")
        #expect(form["album[1]"] == nil)
        #expect(form["timestamp[1]"] == "1700000060")
        #expect(form["chosenByUser[0]"] == "0")
    }

    @Test func singleScrobbleObjectAndDailyLimit() async throws {   // Review Focus 5
        let stub = StubTransport([
            .init(body: ##"{"scrobbles":{"scrobble":{"ignoredMessage":{"code":0,"#text":""}},"@attr":{"accepted":1}}}"##),
            .init(body: ##"{"scrobbles":{"scrobble":{"ignoredMessage":{"code":"5","#text":"Daily scrobble limit exceeded"}}}}"##),
        ])
        #expect(try await client(stub).scrobble([item("One")]) == [.accepted])
        #expect(try await client(stub).scrobble([item("Two")]) == [.dailyLimit])
    }

    @Test(arguments: [
        (200, #"{"error":9,"message":"Invalid session key"}"#, ScrobbleError.signedOut),
        (403, #"{"error":26,"message":"Suspended API key"}"#, ScrobbleError.keyUnusable(code: 26)),
        (503, "<html>down</html>", ScrobbleError.transient("HTTP 503")),
        (429, "", ScrobbleError.rateLimited(retryAfter: nil)),
        (200, "not json", ScrobbleError.transient("Unreadable response from ws.audioscrobbler.com")),
    ])
    func errorsAreClassified(status: Int, body: String, expected: ScrobbleError) async {   // Review Focus 5
        let stub = StubTransport([.init(status: status, body: body)])
        await #expect(throws: expected) { _ = try await client(stub).scrobble([item("One")]) }
    }

    @Test func otherPlayerDetection() async throws {   // #22, Review Focus 1
        let playing = ##"{"recenttracks":{"track":[{"artist":{"#text":"Air"},"name":"Kelly","@attr":{"nowplaying":"true"}},{"artist":{"#text":"X"},"name":"Y"}]}}"##
        let single = ##"{"recenttracks":{"track":{"artist":{"#text":"Air"},"name":"Kelly"}}}"##
        let stub = StubTransport([.init(body: playing), .init(body: playing), .init(body: single)])
        let c = client(stub)
        #expect(try await c.isOtherPlayerActive(excluding: nil) == true)
        #expect(try await c.isOtherPlayerActive(excluding: Track(artist: "air", title: "KELLY")) == false)
        #expect(try await c.isOtherPlayerActive(excluding: nil) == false)
        let other = StubTransport([.init(body: playing)])
        #expect(try await client(other).isOtherPlayerActive(excluding: Track(artist: "Other", title: "Song")) == true)
        let request = await stub.requests[0]
        #expect(request.httpMethod == "GET")
        #expect(request.url?.query?.contains("method=user.getRecentTracks") == true)
        #expect(request.url?.query?.contains("api_sig") == false)
    }

    @Test func cancellationIsNotWrapped() async {
        let stub = StubTransport([.init(body: "", error: CancellationError()), .init(body: "", error: CancellationError())])
        await #expect(throws: CancellationError.self) { _ = try await client(stub).scrobble([item("One")]) }
        await #expect(throws: CancellationError.self) { try await client(stub).nowPlaying(Track(artist: "A", title: "B")) }
    }
}
