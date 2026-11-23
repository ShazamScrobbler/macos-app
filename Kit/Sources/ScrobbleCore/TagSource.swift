import Foundation

public enum LibraryStatus: Equatable, Sendable {
    case ok
    case notInstalled
    case noLibraryYet
    case accessDenied
    case unsupportedSchema(String)
    case unreadable(String)
}

public struct TagSourceResult: Sendable, Equatable {
    public var status: LibraryStatus
    /// Tags strictly newer than the requested date, oldest first.
    public var tagsSince: [ShazamTag]
    /// Most recent tags, newest first.
    public var recent: [ShazamTag]

    public init(status: LibraryStatus, tagsSince: [ShazamTag] = [], recent: [ShazamTag] = []) {
        self.status = status
        self.tagsSince = tagsSince
        self.recent = recent
    }
}

public protocol TagSource: Sendable {
    func read(since: Date, recentLimit: Int) -> TagSourceResult
    /// Lookup by Shazam row id; used once to migrate 1.x markers (§8).
    func tags(withPKs pks: [Int64]) -> [Int64: ShazamTag]
}
