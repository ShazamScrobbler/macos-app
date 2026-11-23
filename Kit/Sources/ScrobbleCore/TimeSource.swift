import Foundation

public protocol TimeSource: Sendable {
    var now: Date { get }
}

public struct SystemTime: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// Deterministic time for tests.
public final class ManualTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date) { current = start }

    public var now: Date { lock.withLock { current } }
    public func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
    public func set(_ date: Date) { lock.withLock { current = date } }
}
