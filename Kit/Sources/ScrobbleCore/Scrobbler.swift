import Foundation

public struct ScrobbleItem: Sendable, Equatable {
    public var key: TagKey
    public var track: Track
    public var date: Date
    public init(key: TagKey, track: Track, date: Date) { self.key = key; self.track = track; self.date = date }
}

public enum ScrobbleItemResult: Sendable, Equatable {
    case accepted
    case ignored(String)
    case dailyLimit
}

/// One configured account's protocol client. Implementations throw `ScrobbleError`.
public protocol Scrobbler: Sendable {
    var maxBatchSize: Int { get }
    /// Tags older than this are rejected by the service (Last.fm: 14 days). `nil` = no limit.
    var maxScrobbleAge: TimeInterval? { get }
    func nowPlaying(_ track: Track) async throws
    /// Returns one result per item, in order.
    func scrobble(_ items: [ScrobbleItem]) async throws -> [ScrobbleItemResult]
    /// True when another app is currently "now playing" on this profile (#22).
    /// `ours` is the track this app last sent as now playing; it never counts as another player.
    func isOtherPlayerActive(excluding ours: Track?) async throws -> Bool
}
