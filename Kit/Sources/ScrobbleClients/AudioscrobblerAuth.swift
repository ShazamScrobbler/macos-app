import Foundation
import ScrobbleCore

public struct AudioscrobblerSession: Sendable, Equatable {
    public var sessionKey: String
    public var username: String
    public init(sessionKey: String, username: String) { self.sessionKey = sessionKey; self.username = username }
}

public enum AudioscrobblerAuthError: Error, Equatable, Sendable {
    case notAuthorizedYet
    case tokenExpired
    case invalidCredentials(String)
    case failed(ScrobbleError)
}

/// Browser sign-in (preferred, no password in the app) and username/password fallback.
public struct AudioscrobblerAuth: Sendable {
    let api: AudioscrobblerAPI

    public init(apiURL: URL, apiKey: String, apiSecret: String, transport: any HTTPTransport) {
        api = AudioscrobblerAPI(apiURL: apiURL, apiKey: apiKey, apiSecret: apiSecret, transport: transport)
    }

    public func getToken() async throws -> String {
        let object = try await perform { try await api.call(method: "auth.getToken", params: [:]) }
        guard let token = object["token"] as? String else { throw AudioscrobblerAuthError.failed(.transient("No token")) }
        return token
    }

    public func authorizationURL(webAuthURL: URL, token: String) -> URL {
        var components = URLComponents(url: webAuthURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api_key", value: api.apiKey), URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    /// Throws `.notAuthorizedYet` until the user approves in the browser; poll every 3 s.
    public func getSession(token: String) async throws -> AudioscrobblerSession {
        try await session(from: perform { try await api.call(method: "auth.getSession", params: ["token": token]) })
    }

    public func getMobileSession(username: String, password: String) async throws -> AudioscrobblerSession {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await session(from: perform {
            try await api.call(method: "auth.getMobileSession", params: ["username": trimmed, "password": password])
        })
    }

    private func session(from object: [String: Any]) throws -> AudioscrobblerSession {
        guard let session = object["session"] as? [String: Any], let key = session["key"] as? String,
              let name = session["name"] as? String else {
            throw AudioscrobblerAuthError.failed(.transient("No session in response"))
        }
        return AudioscrobblerSession(sessionKey: key, username: name)
    }

    private func perform(_ body: () async throws -> [String: Any]) async throws -> [String: Any] {
        do { return try await body() }
        catch let error as AudioscrobblerCallError {
            switch error.code {
            case 14: throw AudioscrobblerAuthError.notAuthorizedYet
            case 15: throw AudioscrobblerAuthError.tokenExpired
            case 4: throw AudioscrobblerAuthError.invalidCredentials(error.message)
            default: throw AudioscrobblerAuthError.failed(error.scrobbleError)
            }
        } catch {
            throw AudioscrobblerAuthError.failed(error.asScrobbleError)
        }
    }
}
