import Foundation

public enum ScrobbleError: Error, Equatable, Sendable {
    case signedOut
    case keyUnusable(code: Int)
    case transient(String)
    case rateLimited(retryAfter: TimeInterval?)
    case permanent(String)
}

extension ScrobbleError {
    /// Only the case name: safe for public logs (the payloads can carry server text or listening history).
    public var logSummary: String {
        switch self {
        case .signedOut: "signedOut"
        case .keyUnusable: "keyUnusable"
        case .transient: "transient"
        case .rateLimited: "rateLimited"
        case .permanent: "permanent"
        }
    }
}

extension Error {
    public var asScrobbleError: ScrobbleError {
        (self as? ScrobbleError) ?? .transient(String(describing: self))
    }
}

public enum Backoff {
    /// 1, 2, 4 … minutes, capped at 60, with ±20 % jitter (`random` in 0..<1).
    public static func delay(attempt: Int, random: Double) -> TimeInterval {
        let minutes = min(60.0, pow(2.0, Double(max(attempt, 1) - 1)))
        return minutes * 60 * (0.8 + 0.4 * random)
    }

    /// A server's retry hint, usable only when finite; clamped to 5 s … 1 h.
    public static func cappedRetryAfter(_ seconds: TimeInterval?) -> TimeInterval? {
        seconds.flatMap { $0.isFinite ? min(max($0, 5), 3600) : nil }
    }

    public static func nextUTCMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }
}

public enum DeliveryPolicy {
    public static func state(after error: ScrobbleError, previous: DeliveryState?, now: Date, random: Double) -> DeliveryState {
        let attempt = (previous?.retryAttempt ?? 0) + 1
        switch error {
        case .signedOut: return .held(.signedOut)
        case .keyUnusable: return .held(.keyUnusable)
        case let .permanent(message): return .ignored(message)
        case .transient: return .retry(attempt: attempt, nextAt: now + Backoff.delay(attempt: attempt, random: random))
        case let .rateLimited(after):
            return .retry(attempt: attempt, nextAt: now + (Backoff.cappedRetryAfter(after) ?? Backoff.delay(attempt: attempt, random: random)))
        }
    }

    public static func problem(for error: ScrobbleError) -> AccountProblem? {
        switch error {
        case .signedOut: .signedOut
        case .keyUnusable: .keyUnusable
        default: nil
        }
    }
}
