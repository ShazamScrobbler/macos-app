import Foundation
import ScrobbleCore

public actor FakeScrobbler: Scrobbler {
    public nonisolated let maxBatchSize: Int
    public nonisolated let maxScrobbleAge: TimeInterval?

    /// Consumed one per `scrobble` call. `.success(nil)` = accept everything.
    public var replies: [Result<[ScrobbleItemResult]?, ScrobbleError>] = []
    public var otherPlayerActive = false
    public var nowPlayingError: ScrobbleError?

    public private(set) var batches: [[ScrobbleItem]] = []
    public private(set) var nowPlayingTracks: [Track] = []
    public private(set) var otherPlayerChecks: [Track?] = []

    public init(maxBatchSize: Int = 50, maxScrobbleAge: TimeInterval? = nil) {
        self.maxBatchSize = maxBatchSize
        self.maxScrobbleAge = maxScrobbleAge
    }

    public func setReplies(_ replies: [Result<[ScrobbleItemResult]?, ScrobbleError>]) { self.replies = replies }
    public func setOtherPlayerActive(_ value: Bool) { otherPlayerActive = value }
    public func setNowPlayingError(_ error: ScrobbleError?) { nowPlayingError = error }

    public func nowPlaying(_ track: Track) async throws {
        if let nowPlayingError { throw nowPlayingError }
        nowPlayingTracks.append(track)
    }

    public func scrobble(_ items: [ScrobbleItem]) async throws -> [ScrobbleItemResult] {
        batches.append(items)
        let reply = replies.isEmpty ? .success(nil) : replies.removeFirst()
        switch reply {
        case let .success(results): return results ?? items.map { _ in .accepted }
        case let .failure(error): throw error
        }
    }

    public func isOtherPlayerActive(excluding ours: Track?) async throws -> Bool {
        otherPlayerChecks.append(ours)
        return otherPlayerActive
    }
}
