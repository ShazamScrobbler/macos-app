import Foundation
import ScrobbleCore

public struct ListenBrainzClient: Scrobbler {
    public let maxBatchSize = 100
    public let maxScrobbleAge: TimeInterval? = nil

    static let clientName = "ShazamScrobbler"

    private let apiURL: URL
    private let token: String
    private let username: String
    private let transport: any HTTPTransport
    private let clientVersion: String

    public init(apiURL: URL, token: String, username: String, transport: any HTTPTransport, clientVersion: String) {
        self.apiURL = apiURL
        self.token = token
        self.username = username
        self.transport = transport
        self.clientVersion = clientVersion
    }

    public static func validate(apiURL: URL, token: String, transport: any HTTPTransport) async throws -> String {
        let object = try await request(apiURL.appendingPathComponent("1/validate-token"), token: token,
                                       method: "GET", body: nil, transport: transport)
        guard object["valid"] as? Bool == true, let name = object["user_name"] as? String else {
            throw ScrobbleError.signedOut
        }
        return name
    }

    public func nowPlaying(_ track: Track) async throws {
        _ = try await submit(type: "playing_now", listens: [listen(track, at: nil)])
    }

    public func scrobble(_ items: [ScrobbleItem]) async throws -> [ScrobbleItemResult] {
        _ = try await submit(type: items.count == 1 ? "single" : "import",
                             listens: items.map { listen($0.track, at: $0.date) })
        return items.map { _ in .accepted }
    }

    public func isOtherPlayerActive(excluding ours: Track?) async throws -> Bool {
        let url = apiURL.appendingPathComponent("1/user").appendingPathComponent(username).appendingPathComponent("playing-now")
        let object = try await Self.request(url, token: token, method: "GET", body: nil, transport: transport)
        let listens = ((object["payload"] as? [String: Any])?["listens"] as? [[String: Any]]) ?? []
        guard let metadata = listens.first?["track_metadata"] as? [String: Any] else { return false }
        let info = metadata["additional_info"] as? [String: Any]
        if info?["submission_client"] as? String == Self.clientName { return false }
        let track = Track(artist: metadata["artist_name"] as? String ?? "", title: metadata["track_name"] as? String ?? "")
        if let ours, ours.matchKey == track.matchKey { return false }
        return true
    }

    /// Deletes a listen we submitted (#7). Needs the listen's msid, which submit-listens doesn't return.
    public func remove(listenedAt date: Date, track: Track) async throws {
        let seconds = Int(date.timeIntervalSince1970)
        var components = URLComponents(url: apiURL.appendingPathComponent("1/user").appendingPathComponent(username)
            .appendingPathComponent("listens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "max_ts", value: String(seconds + 1)), URLQueryItem(name: "count", value: "10")]
        let object = try await Self.request(components.url!, token: token, method: "GET", body: nil, transport: transport)
        let listens = ((object["payload"] as? [String: Any])?["listens"] as? [[String: Any]]) ?? []
        let match = listens.first { listen in
            let metadata = listen["track_metadata"] as? [String: Any]
            let candidate = Track(artist: metadata?["artist_name"] as? String ?? "", title: metadata?["track_name"] as? String ?? "")
            return listen["listened_at"] as? Int == seconds && candidate.matchKey == track.matchKey
        }
        guard let msid = match?["recording_msid"] as? String else { throw ScrobbleError.permanent("Listen not found") }
        _ = try await Self.request(apiURL.appendingPathComponent("1/delete-listen"), token: token, method: "POST",
                                   body: ["listened_at": seconds, "recording_msid": msid], transport: transport)
    }

    private func submit(type: String, listens: [[String: Any]]) async throws -> [String: Any] {
        try await Self.request(apiURL.appendingPathComponent("1/submit-listens"), token: token, method: "POST",
                               body: ["listen_type": type, "payload": listens], transport: transport)
    }

    private func listen(_ track: Track, at date: Date?) -> [String: Any] {
        var metadata: [String: Any] = [
            "artist_name": track.artist,
            "track_name": track.title,
            "additional_info": ["submission_client": Self.clientName, "submission_client_version": clientVersion,
                                "media_player": "Shazam"],
        ]
        if let album = track.album { metadata["release_name"] = album }
        var listen: [String: Any] = ["track_metadata": metadata]
        if let date { listen["listened_at"] = Int(date.timeIntervalSince1970) }
        return listen
    }

    private static func request(_ url: URL, token: String, method: String, body: [String: Any]?,
                                transport: any HTTPTransport) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw ScrobbleError.transient(error.localizedDescription) }
        let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let object = parsed ?? [:]
        switch response.statusCode {
        case 200..<300:
            // A login page or proxy answer with a 2xx status is not an accepted listen.
            guard parsed != nil else { throw ScrobbleError.transient("Unreadable response from \(url.host ?? "server")") }
            return object
        case 401: throw ScrobbleError.signedOut
        case 429:
            let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset-In").flatMap(TimeInterval.init)
            throw ScrobbleError.rateLimited(retryAfter: reset)
        case 400..<500: throw ScrobbleError.permanent(object["error"] as? String ?? "Rejected (HTTP \(response.statusCode))")
        default: throw ScrobbleError.transient("HTTP \(response.statusCode)")
        }
    }
}