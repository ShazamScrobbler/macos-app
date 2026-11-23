import Foundation

public struct AccountCursor: Sendable, Equatable {
    public var id: AccountID
    public var since: Date
    public init(id: AccountID, since: Date) { self.id = id; self.since = since }
}

public struct NowPlayingRecord: Sendable, Equatable {
    public var key: TagKey
    public var sentAt: Date
    public init(key: TagKey, sentAt: Date) { self.key = key; self.sentAt = sentAt }
}

public struct EngineInput: Sendable {
    /// Callers must include at least `EngineSettings.duplicateWindow` (600 s) of tag history before the
    /// oldest account cursor, so duplicates and "following" tags are seen.
    public var tags: [ShazamTag]
    public var now: Date
    public var settings: EngineSettings
    public var accounts: [AccountCursor]
    public var states: [TagKey: [AccountID: DeliveryState]]
    public var excluded: Set<TagKey>
    public var forced: Set<TagKey>
    public var lastNowPlaying: [AccountID: NowPlayingRecord]

    public init(tags: [ShazamTag], now: Date, settings: EngineSettings, accounts: [AccountCursor],
                states: [TagKey: [AccountID: DeliveryState]] = [:], excluded: Set<TagKey> = [],
                forced: Set<TagKey> = [], lastNowPlaying: [AccountID: NowPlayingRecord] = [:]) {
        self.tags = tags
        self.now = now
        self.settings = settings
        self.accounts = accounts
        self.states = states
        self.excluded = excluded
        self.forced = forced
        self.lastNowPlaying = lastNowPlaying
    }
}

public struct Transition: Sendable, Equatable {
    public var key: TagKey
    public var tag: ShazamTag
    public var account: AccountID
    public var to: DeliveryState
    public init(key: TagKey, tag: ShazamTag, account: AccountID, to: DeliveryState) {
        self.key = key; self.tag = tag; self.account = account; self.to = to
    }
}

public struct NowPlayingRequest: Sendable, Equatable {
    public var account: AccountID
    public var tag: ShazamTag
    public var isRefresh: Bool
    public init(account: AccountID, tag: ShazamTag, isRefresh: Bool) {
        self.account = account; self.tag = tag; self.isRefresh = isRefresh
    }
}

public struct EngineOutput: Sendable, Equatable {
    public var transitions: [Transition]
    public var nowPlaying: [NowPlayingRequest]
    public var nextWake: Date?
    public init(transitions: [Transition], nowPlaying: [NowPlayingRequest], nextWake: Date?) {
        self.transitions = transitions; self.nowPlaying = nowPlaying; self.nextWake = nextWake
    }
}

/// Pure scrobbling rules (spec §5). No I/O, no clock: everything comes in through `EngineInput`.
public enum ScrobbleEngine {
    public static func evaluate(_ input: EngineInput) -> EngineOutput {
        let settings = input.settings
        let sorted = input.tags.sorted { ($0.date, $0.pk) < ($1.date, $1.pk) }

        var seenKeys = Set<TagKey>()
        let unique = sorted.filter { seenKeys.insert($0.key).inserted }

        var lastPlay: ShazamTag?
        var lastSighting = Date.distantPast
        var duplicates = Set<TagKey>()
        for tag in unique {
            if let previous = lastPlay, previous.track.matchKey == tag.track.matchKey,
               tag.date.timeIntervalSince(lastSighting) < EngineSettings.duplicateWindow {
                duplicates.insert(tag.key)
                lastSighting = tag.date
            } else {
                lastPlay = tag
                lastSighting = tag.date
            }
        }

        let plays = unique.filter { !duplicates.contains($0.key) }
        var following: [TagKey: ShazamTag] = [:]
        for (index, tag) in plays.enumerated() where index + 1 < plays.count {
            following[tag.key] = plays[index + 1]
        }

        var transitions: [Transition] = []
        var resulting: [TagKey: [AccountID: DeliveryState]] = input.states
        var earliestWake: Date?
        func wake(at date: Date) {
            guard date > input.now else { return }
            earliestWake = min(earliestWake ?? date, date)
        }

        for tag in unique {
            for account in input.accounts where tag.date > account.since {
                let current = input.states[tag.key]?[account.id]
                let next = nextState(for: tag, current: current, isDuplicate: duplicates.contains(tag.key),
                                     following: following[tag.key], input: input)
                guard let next else { continue }
                if next != current {
                    transitions.append(Transition(key: tag.key, tag: tag, account: account.id, to: next))
                    resulting[tag.key, default: [:]][account.id] = next
                }
                if case let .nowPlaying(deadline) = next { wake(at: deadline) }
            }
        }

        var requests: [NowPlayingRequest] = []
        if let newest = plays.last, !settings.paused,
           input.now.timeIntervalSince(newest.date) < EngineSettings.nowPlayingCap {
            for account in input.accounts where newest.date > account.since {
                guard let state = resulting[newest.key]?[account.id], allowsNowPlaying(state) else { continue }
                let last = input.lastNowPlaying[account.id]
                if last?.key == newest.key, let sentAt = last?.sentAt {
                    let due = sentAt + EngineSettings.nowPlayingResendInterval
                    if input.now >= due {
                        requests.append(NowPlayingRequest(account: account.id, tag: newest, isRefresh: true))
                        scheduleRefresh(from: input.now, tag: newest, wake: wake(at:))
                    } else {
                        scheduleRefresh(from: sentAt, tag: newest, wake: wake(at:))
                    }
                } else if case .nowPlaying = state {
                    requests.append(NowPlayingRequest(account: account.id, tag: newest, isRefresh: false))
                    scheduleRefresh(from: input.now, tag: newest, wake: wake(at:))
                }
            }
        }

        return EngineOutput(transitions: transitions, nowPlaying: requests, nextWake: earliestWake)
    }

    private static func scheduleRefresh(from sentAt: Date, tag: ShazamTag, wake: (Date) -> Void) {
        let next = sentAt + EngineSettings.nowPlayingResendInterval
        if next.timeIntervalSince(tag.date) < EngineSettings.nowPlayingCap { wake(next) }
    }

    private static func allowsNowPlaying(_ state: DeliveryState) -> Bool {
        switch state {
        case .nowPlaying, .waiting, .retry, .scrobbled: true
        case .tooShort, .skipped, .ignored, .held: false
        }
    }

    private static func nextState(for tag: ShazamTag, current: DeliveryState?, isDuplicate: Bool,
                                  following: ShazamTag?, input: EngineInput) -> DeliveryState? {
        if input.excluded.contains(tag.key) {
            switch current {
            case nil: return isDuplicate ? .skipped(.duplicate) : .skipped(.user)
            case .nowPlaying?, .waiting?, .retry?, .held?: return .skipped(.user)
            default: return current   // final states stay as they are
            }
        }
        switch current {
        case nil:
            if isDuplicate { return .skipped(.duplicate) }
            if input.settings.paused && input.settings.pauseMode == .ignore { return .skipped(.paused) }
            return playState(for: tag, following: following, input: input)
        case .nowPlaying?:
            return playState(for: tag, following: following, input: input)
        case .skipped(.user)?:
            // No longer excluded: re-evaluate like a new row (paused rule not applied, the user asked for it).
            if input.forced.contains(tag.key) { return .waiting }
            if isDuplicate { return .skipped(.duplicate) }
            return playState(for: tag, following: following, input: input)
        case .tooShort?, .skipped?:
            return input.forced.contains(tag.key) ? .waiting : current
        default:
            return current
        }
    }

    private static func playState(for tag: ShazamTag, following: ShazamTag?, input: EngineInput) -> DeliveryState {
        if let next = following {
            return next.date.timeIntervalSince(tag.date) < input.settings.minPlayTime ? .tooShort : .waiting
        }
        let deadline = tag.date + input.settings.minPlayTime
        return input.now < deadline ? .nowPlaying(deadline: deadline) : .waiting
    }
}
