import Foundation
import ScrobbleCore

public struct AudioscrobblerClient: Scrobbler {
    public let maxBatchSize = 50
    public let maxScrobbleAge: TimeInterval? = 14 * 86_400

    private let api: AudioscrobblerAPI
    private let sessionKey: String
    private let username: String

    public init(apiURL: URL, apiKey: String, apiSecret: String, sessionKey: String, username: String,
                transport: any HTTPTransport) {
        api = AudioscrobblerAPI(apiURL: apiURL, apiKey: apiKey, apiSecret: apiSecret, transport: transport)
        self.sessionKey = sessionKey
        self.username = username
    }

    public func nowPlaying(_ track: Track) async throws {
        var params = ["artist": track.artist, "track": track.title]
        if let album = track.album { params["album"] = album }
        // No duration: Last.fm would expire now playing after it (#47).
        _ = try await perform { try await api.call(method: "track.updateNowPlaying", params: params, sessionKey: sessionKey) }
    }

    public func scrobble(_ items: [ScrobbleItem]) async throws -> [ScrobbleItemResult] {
        var params: [String: String] = [:]
        for (index, item) in items.enumerated() {
            params["artist[\(index)]"] = item.track.artist
            params["track[\(index)]"] = item.track.title
            params["timestamp[\(index)]"] = String(item.date.epochSeconds)
            params["chosenByUser[\(index)]"] = "0"
            if let album = item.track.album { params["album[\(index)]"] = album }
        }
        let object = try await perform { try await api.call(method: "track.scrobble", params: params, sessionKey: sessionKey) }

        let scrobbles = AudioscrobblerAPI.array((object["scrobbles"] as? [String: Any])?["scrobble"])
        guard scrobbles.count == items.count else {
            throw ScrobbleError.transient("Expected \(items.count) results, got \(scrobbles.count)")
        }
        return scrobbles.map { scrobble in
            let ignored = scrobble["ignoredMessage"] as? [String: Any]
            let code = AudioscrobblerAPI.int(ignored?["code"]) ?? 0
            let text = (ignored?["#text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            switch code {
            case 0: return .accepted
            case 5: return .dailyLimit
            case 1: return .ignored(text ?? "Artist was ignored")
            case 2: return .ignored(text ?? "Track was ignored")
            case 3: return .ignored(text ?? "Timestamp too old")
            case 4: return .ignored(text ?? "Timestamp too new")
            default: return .ignored(text ?? "Ignored (code \(code))")
            }
        }
    }

    public func isOtherPlayerActive(excluding ours: Track?) async throws -> Bool {
        let object = try await perform {
            try await api.call(method: "user.getRecentTracks", params: ["user": username, "limit": "1"],
                               signed: false, get: true)
        }
        let tracks = AudioscrobblerAPI.array((object["recenttracks"] as? [String: Any])?["track"])
        guard let playing = tracks.first(where: { ($0["@attr"] as? [String: Any])?["nowplaying"] as? String == "true" }) else {
            return false
        }
        let artistObject = playing["artist"] as? [String: Any]
        let artist = artistObject?["#text"] as? String ?? artistObject?["name"] as? String ?? ""
        let title = playing["name"] as? String ?? ""
        if let ours, Track(artist: artist, title: title).matchKey == ours.matchKey { return false }
        return true
    }

    /// Cancellation passes through unchanged; every other failure becomes a ScrobbleError.
    private func perform(_ body: () async throws -> [String: Any]) async throws -> [String: Any] {
        do { return try await body() }
        catch is CancellationError { throw CancellationError() }
        catch { throw error.audioscrobblerError }
    }
}
