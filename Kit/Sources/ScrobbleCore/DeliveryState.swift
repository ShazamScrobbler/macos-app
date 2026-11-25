import Foundation

public enum SkipReason: String, Codable, Sendable {
    case paused, user, otherPlayer, duplicate
}

public enum AccountProblem: String, Codable, Sendable, Error {
    case signedOut
    case keyUnusable
}

/// Status of one tag for one account (§5).
public enum DeliveryState: Equatable, Codable, Sendable {
    case waiting
    case nowPlaying(deadline: Date)
    case scrobbled(at: Date)
    case tooShort
    case skipped(SkipReason)
    case ignored(String)
    case held(AccountProblem)
    case retry(attempt: Int, nextAt: Date)

    /// Final states are never changed by the engine or delivery again
    /// (only by an explicit user action such as "Scrobble Anyway").
    public var isFinal: Bool {
        switch self {
        case .scrobbled, .tooShort, .skipped, .ignored: true
        case .waiting, .nowPlaying, .held, .retry: false
        }
    }
}
