import Foundation

/// Serializes scans: a trigger during a running scan queues exactly one more run.
public actor RescanGate {
    private var running = false
    private var pending = false

    public init() {}

    public func trigger(_ body: @Sendable () async -> Void) async {
        if running {
            pending = true
            return
        }
        running = true
        repeat {
            pending = false
            await body()
        } while pending
        running = false
    }
}
