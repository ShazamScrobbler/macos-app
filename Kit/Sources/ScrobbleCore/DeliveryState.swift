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
    /// Waiting after a transient failure (offline, server error, rate limit). Made due at once by a reconnect,
    /// wake, new tag or fixed account (`StateStore.makeTransientRetriesDue`).
    case retry(attempt: Int, nextAt: Date)
    /// Waiting for the service's daily scrobble limit to reset (next UTC midnight). Never made due early.
    /// A separate case (stored with kind "retry") so rows written before it existed still decode as `.retry`.
    case retryAfterDailyLimit(attempt: Int, nextAt: Date)

    /// Final states are never changed by the engine or delivery again
    /// (only by an explicit user action such as "Scrobble Anyway").
    public var isFinal: Bool {
        switch self {
        case .scrobbled, .tooShort, .skipped, .ignored: true
        case .waiting, .nowPlaying, .held, .retry, .retryAfterDailyLimit: false
        }
    }

    /// The attempt count of either retry kind; nil otherwise.
    public var retryAttempt: Int? {
        switch self {
        case let .retry(attempt, _), let .retryAfterDailyLimit(attempt, _): attempt
        default: nil
        }
    }
}
