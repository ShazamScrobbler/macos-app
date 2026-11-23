import Foundation
import Testing
import ScrobbleCore
@testable import ScrobbleClients

@Suite struct ListenBrainzClientTests {
    let api = URL(string: "https://api.listenbrainz.org")!
    let t = Date(timeIntervalSince1970: 1_700_000_000)

    func client(_ stub: StubTransport) -> ListenBrainzClient {
        ListenBrainzClient(apiURL: api, token: "TOKEN", username: "steph", transport: stub, clientVersion: "2.0.0")
    }
    func item(_ title: String, at offset: TimeInterval = 0, album: String? = nil) -> ScrobbleItem {
        let track = Track(artist: "Air", title: title, album: album)
        return ScrobbleItem(key: TagKey(date: t + offset, track: track), track: track, date: t + offset)
    }

    @Test func validateReturnsUsernameOrSignedOut() async throws {
        let stub = StubTransport([
            .init(body: #"{"code":200,"message":"Token valid.","valid":true,"user_name":"steph"}"#),
            .init(body: #"{"code":200,"message":"Token invalid.","valid":false}"#),
        ])
        #expect(try await ListenBrainzClient.validate(apiURL: api, token: "T", transport: stub) == "steph")
        await #expect(throws: ScrobbleError.signedOut) { _ = try await ListenBrainzClient.validate(apiURL: api, token: "T", transport: stub) }
        let request = await stub.requests[0]
        #expect(request.url?.absoluteString == "https://api.listenbrainz.org/1/validate-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token T")
    }

    @Test func singleVersusImportPayloads() async throws {
        let stub = StubTransport([.init(body: #"{"status":"ok"}"#), .init(body: #"{"status":"ok"}"#)])
        let c = client(stub)
        #expect(try await c.scrobble([item("Kelly", album: "Moon Safari")]) == [.accepted])
        #expect(try await c.scrobble([item("A"), item("B", at: 60)]) == [.accepted, .accepted])
        let first = await stub.json(0)
        #expect(first["listen_type"] as? String == "single")
        let listen = (first["payload"] as? [[String: Any]])?.first
        #expect(listen?["listened_at"] as? Int == 1_700_000_000)
        let metadata = listen?["track_metadata"] as? [String: Any]
        #expect(metadata?["artist_name"] as? String == "Air")
        #expect(metadata?["release_name"] as? String == "Moon Safari")
        #expect((metadata?["additional_info"] as? [String: Any])?["submission_client"] as? String == "ShazamScrobbler")
        #expect(await stub.json(1)["listen_type"] as? String == "import")
    }

    @Test func nowPlayingHasNoTimestamp() async throws {
        let stub = StubTransport([.init(body: #"{"status":"ok"}"#)])
        try await client(stub).nowPlaying(Track(artist: "Air", title: "Kelly"))
        let body = await stub.json(0)
        #expect(body["listen_type"] as? String == "playing_now")
        #expect((body["payload"] as? [[String: Any]])?.first?["listened_at"] == nil)
    }

    @Test(arguments: [
        (401, #"{"code":401,"error":"Invalid authorization token."}"#, [String: String](), ScrobbleError.signedOut),
        (400, #"{"code":400,"error":"Value for key listened_at is too low."}"#, [:], ScrobbleError.permanent("Value for key listened_at is too low.")),
        (429, "", ["X-RateLimit-Reset-In": "12"], ScrobbleError.rateLimited(retryAfter: 12)),
        (502, "bad gateway", [:], ScrobbleError.transient("HTTP 502")),
    ])
    func errorsAreClassified(status: Int, body: String, headers: [String: String], expected: ScrobbleError) async {
        let stub = StubTransport([.init(status: status, body: body, headers: headers)])
        await #expect(throws: expected) { _ = try await client(stub).scrobble([item("Kelly")]) }
    }

    @Test func nonJSONSuccessIsTransientNotAccepted() async {
        let stub = StubTransport([.init(status: 200, body: "<html>Please log in</html>")])
        await #expect(throws: ScrobbleError.transient("Unreadable response from api.listenbrainz.org")) {
            _ = try await client(stub).scrobble([item("Kelly")])
        }
    }

    @Test func otherPlayerIgnoresOurOwnClientAndOurTrack() async throws {   // #22, Review Focus 1
        func playingNow(client: String, title: String) -> StubTransport.Reply {
            .init(body: """
                {"payload":{"count":1,"listens":[{"track_metadata":{"artist_name":"Air","track_name":"\(title)",
                  "additional_info":{"submission_client":"\(client)"}}}]}}
                """)
        }
        let stub = StubTransport([
            playingNow(client: "Spotify", title: "Kelly"),
            playingNow(client: "ShazamScrobbler", title: "Kelly"),
            playingNow(client: "Spotify", title: "Kelly"),
            .init(body: #"{"payload":{"count":0,"listens":[]}}"#),
        ])
        let c = client(stub)
        #expect(try await c.isOtherPlayerActive(excluding: nil) == true)
        #expect(try await c.isOtherPlayerActive(excluding: nil) == false)
        #expect(try await c.isOtherPlayerActive(excluding: Track(artist: "air", title: "kelly")) == false)
        #expect(try await c.isOtherPlayerActive(excluding: nil) == false)
        #expect(await stub.requests[0].url?.path == "/1/user/steph/playing-now")
    }

    @Test func removeFindsMsidThenDeletes() async throws {   // #7
        let stub = StubTransport([
            .init(body: """
                {"payload":{"listens":[
                  {"listened_at":1700000000,"recording_msid":"MSID-1","track_metadata":{"artist_name":"Air","track_name":"Kelly"}},
                  {"listened_at":1699999000,"recording_msid":"MSID-0","track_metadata":{"artist_name":"Air","track_name":"Kelly"}}]}}
                """),
            .init(body: #"{"status":"ok"}"#),
        ])
        try await client(stub).remove(listenedAt: t, track: Track(artist: "Air", title: "Kelly"))
        let lookup = await stub.requests[0]
        #expect(lookup.url?.query?.contains("max_ts=1700000001") == true)
        let delete = await stub.json(1)
        #expect(delete["recording_msid"] as? String == "MSID-1")
        #expect(delete["listened_at"] as? Int == 1_700_000_000)
    }

    @Test func cancellationPropagatesAsCancellationError() async {
        let stub = StubTransport([.init(body: "", error: CancellationError())])
        await #expect(throws: CancellationError.self) { _ = try await client(stub).scrobble([item("Kelly")]) }
        let urlCancelled = StubTransport([.init(body: "", error: URLError(.cancelled))])
        await #expect(throws: CancellationError.self) { _ = try await client(urlCancelled).scrobble([item("Kelly")]) }
    }
}
