import Foundation
import Testing
import ScrobbleCore
@testable import ScrobbleClients

@Suite struct AudioscrobblerAuthTests {
    let api = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    @Test func signatureMatchesLastFmAlgorithm() {
        #expect(AudioscrobblerSignature.sign(
            ["api_key": "xxxxxxxxxx", "method": "auth.getSession", "token": "yyyyyyyyyy", "format": "json"],
            secret: "ilovecher") == "dc8837f76dba853ce9f2b0be643b1505")
        #expect(AudioscrobblerSignature.sign(
            ["method": "track.scrobble", "api_key": "KEY", "sk": "SK", "artist[0]": "Daft Punk",
             "track[0]": "Digital Love", "timestamp[0]": "1700000000", "album[0]": "Discovery"],
            secret: "SECRET") == "b436ea383b40c10107228aa07a6f5e20")
    }

    @Test func formEncodingRoundTripsReservedCharacters() {
        let params = ["artist": "Simon & Garfunkel", "track": "50% = ½ + ?", "x": "a+b c"]
        #expect(FormEncoding.decode(FormEncoding.encode(params)) == params)
    }

    @Test func webAuthFlow() async throws {
        let stub = StubTransport([
            .init(body: #"{"token":"TOK"}"#),
            .init(body: #"{"error":14,"message":"This token has not been authorized"}"#),
            .init(body: #"{"session":{"name":"stephane","key":"SESSION","subscriber":0}}"#),
        ])
        let auth = AudioscrobblerAuth(apiURL: api, apiKey: "KEY", apiSecret: "SECRET", transport: stub)
        let token = try await auth.getToken()
        #expect(token == "TOK")
        #expect(auth.authorizationURL(webAuthURL: URL(string: "https://www.last.fm/api/auth/")!, token: token).absoluteString
                == "https://www.last.fm/api/auth/?api_key=KEY&token=TOK")
        await #expect(throws: AudioscrobblerAuthError.notAuthorizedYet) { try await auth.getSession(token: token) }
        #expect(try await auth.getSession(token: token) == AudioscrobblerSession(sessionKey: "SESSION", username: "stephane"))
        let form = await stub.form(2)
        #expect(form["method"] == "auth.getSession")
        #expect(form["token"] == "TOK")
        #expect(form["api_sig"] == AudioscrobblerSignature.sign(form.filter { $0.key != "api_sig" }, secret: "SECRET"))
    }

    @Test func expiredTokenAndBadPassword() async throws {
        let stub = StubTransport([
            .init(status: 403, body: #"{"error":15,"message":"This token has expired"}"#),
            .init(status: 403, body: #"{"error":4,"message":"Authentication Failed - You do not have permissions"}"#),
        ])
        let auth = AudioscrobblerAuth(apiURL: api, apiKey: "KEY", apiSecret: "SECRET", transport: stub)
        await #expect(throws: AudioscrobblerAuthError.tokenExpired) { try await auth.getSession(token: "T") }
        await #expect(throws: AudioscrobblerAuthError.invalidCredentials("Authentication Failed - You do not have permissions")) {
            try await auth.getMobileSession(username: "u", password: "p")
        }
    }

    @Test func mobileSessionTrimsUsernameAndPostsOverHTTPS() async throws {   // #39
        let stub = StubTransport([.init(body: #"{"session":{"name":"Steph","key":"SK"}}"#)])
        let auth = AudioscrobblerAuth(apiURL: api, apiKey: "KEY", apiSecret: "SECRET", transport: stub)
        let session = try await auth.getMobileSession(username: "  Steph ", password: "pw")
        #expect(session == AudioscrobblerSession(sessionKey: "SK", username: "Steph"))
        let request = await stub.requests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.scheme == "https")
        #expect(await stub.form(0)["username"] == "Steph")
    }

    @Test func errorCodesMapToScrobbleErrors() {
        #expect(AudioscrobblerAPI.mapError(code: 9, message: "m") == .signedOut)
        #expect(AudioscrobblerAPI.mapError(code: 10, message: "m") == .keyUnusable(code: 10))
        #expect(AudioscrobblerAPI.mapError(code: 26, message: "m") == .keyUnusable(code: 26))
        #expect(AudioscrobblerAPI.mapError(code: 13, message: "m") == .keyUnusable(code: 13))
        #expect(AudioscrobblerAPI.mapError(code: 11, message: "m") == .transient("m"))
        #expect(AudioscrobblerAPI.mapError(code: 16, message: "m") == .transient("m"))
        #expect(AudioscrobblerAPI.mapError(code: 29, message: "m") == .rateLimited(retryAfter: nil))
        #expect(AudioscrobblerAPI.mapError(code: 6, message: "Invalid parameters") == .permanent("Invalid parameters"))
    }

    @Test func passwordSignInRefusesNonHTTPS() async throws {
        let stub = StubTransport([.init(body: #"{"session":{"name":"u","key":"SK"}}"#)])
        let auth = AudioscrobblerAuth(apiURL: URL(string: "http://example.com/2.0/")!, apiKey: "KEY", apiSecret: "SECRET", transport: stub)
        await #expect(throws: AudioscrobblerAuthError.failed(.permanent("Password sign-in requires an https:// server address"))) {
            try await auth.getMobileSession(username: "u", password: "p")
        }
        #expect(await stub.requests.isEmpty)
    }

    @Test func cancellationPropagates() async throws {
        for error in [CancellationError() as any Error, URLError(.cancelled)] {
            let stub = StubTransport([.init(body: "", error: error)])
            let auth = AudioscrobblerAuth(apiURL: api, apiKey: "KEY", apiSecret: "SECRET", transport: stub)
            await #expect(throws: CancellationError.self) { try await auth.getToken() }
        }
    }
}
