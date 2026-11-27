import Foundation

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var engineSettings: EngineSettings {
        get {
            let stored = defaults.object(forKey: "minPlayTime") as? Double ?? 45
            return EngineSettings(
                paused: defaults.bool(forKey: "paused"),
                pauseMode: PauseMode(rawValue: defaults.string(forKey: "pauseMode") ?? "") ?? .ignore,
                minPlayTime: Self.clamp(stored))
        }
        set {
            defaults.set(newValue.paused, forKey: "paused")
            defaults.set(newValue.pauseMode.rawValue, forKey: "pauseMode")
            defaults.set(Self.clamp(newValue.minPlayTime), forKey: "minPlayTime")
        }
    }

    public var notifyNowPlaying: Bool {
        get { defaults.bool(forKey: "notifyNowPlaying") }
        set { defaults.set(newValue, forKey: "notifyNowPlaying") }
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(max(value, EngineSettings.minPlayTimeRange.lowerBound), EngineSettings.minPlayTimeRange.upperBound)
    }
}
