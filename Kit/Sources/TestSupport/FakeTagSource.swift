import Foundation
import ScrobbleCore

public struct FakeTagSource: TagSource {
    public var result: TagSourceResult
    public var byPK: [Int64: ShazamTag]
    public var lookupError: (any Error)?

    public init(result: TagSourceResult = TagSourceResult(status: .ok), byPK: [Int64: ShazamTag] = [:]) {
        self.result = result
        self.byPK = byPK
    }

    public func read(since: Date, recentLimit: Int) -> TagSourceResult { result }
    public func tags(withPKs pks: [Int64]) throws -> [Int64: ShazamTag] {
        if let lookupError { throw lookupError }
        return byPK.filter { pks.contains($0.key) }
    }
}
