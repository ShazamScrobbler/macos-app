import Foundation

public enum PauseMode: String, Codable, Sendable {
    case ignore   // tags detected while paused are skipped (default, #17)
    case keep     // tags detected while paused wait for resume
}

public struct EngineSettings: Equatable, Sendable {
    public var paused: Bool
    public var pauseMode: PauseMode
    public var minPlayTime: TimeInterval

    public static let nowPlayingResendInterval: TimeInterval = 240
    public static let nowPlayingCap: TimeInterval = 600
    public static let duplicateWindow: TimeInterval = 600
    public static let minPlayTimeRange: ClosedRange<TimeInterval> = 30...240

    public init(paused: Bool = false, pauseMode: PauseMode = .ignore, minPlayTime: TimeInterval = 45) {
        self.paused = paused
        self.pauseMode = pauseMode
        self.minPlayTime = minPlayTime
    }
}
