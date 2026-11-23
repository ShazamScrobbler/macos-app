import Foundation

public struct AccountID: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func new() -> AccountID { AccountID(rawValue: UUID().uuidString) }
    public var description: String { rawValue }
}

public enum ProtocolFamily: String, Codable, Sendable {
    case audioscrobbler
    case listenBrainz
}

public enum ServicePreset: String, Codable, Sendable, CaseIterable {
    case lastfm, librefm, customAudioscrobbler, listenbrainz, customListenBrainz

    public var family: ProtocolFamily {
        switch self {
        case .lastfm, .librefm, .customAudioscrobbler: .audioscrobbler
        case .listenbrainz, .customListenBrainz: .listenBrainz
        }
    }

    public var defaultAPIURL: URL? {
        switch self {
        case .lastfm: URL(string: "https://ws.audioscrobbler.com/2.0/")
        case .librefm: URL(string: "https://libre.fm/2.0/")
        case .listenbrainz: URL(string: "https://api.listenbrainz.org")
        case .customAudioscrobbler, .customListenBrainz: nil
        }
    }

    public var defaultWebAuthURL: URL? {
        switch self {
        case .lastfm: URL(string: "https://www.last.fm/api/auth/")
        case .librefm: URL(string: "https://libre.fm/api/auth/")
        default: nil
        }
    }
}

public enum KeyMode: String, Codable, Sendable {
    case builtIn
    case own
}

public struct Account: Codable, Identifiable, Hashable, Sendable {
    public var id: AccountID
    public var preset: ServicePreset
    public var username: String
    public var apiURL: URL
    public var webAuthURL: URL?
    public var keyMode: KeyMode
    public var addedAt: Date

    public init(id: AccountID, preset: ServicePreset, username: String, apiURL: URL,
                webAuthURL: URL?, keyMode: KeyMode, addedAt: Date) {
        self.id = id
        self.preset = preset
        self.username = username
        self.apiURL = apiURL
        self.webAuthURL = webAuthURL
        self.keyMode = keyMode
        self.addedAt = addedAt
    }
}
