import Foundation

public struct NowPlayingInfo: Sendable, Equatable {
    public var tag: ShazamTag
    public var deadline: Date
}

public struct Snapshot: Sendable, Equatable {
    public var libraryStatus: LibraryStatus
    public var recent: [ShazamTag]
    public var states: [TagKey: [AccountID: DeliveryState]]
    public var excluded: Set<TagKey>
    public var problems: [AccountID: AccountProblem]
    public var waitingCount: Int
    public var nowPlaying: NowPlayingInfo?
    public var nextWake: Date?
    public var paused: Bool

    public static let empty = Snapshot(libraryStatus: .noLibraryYet, recent: [], states: [:], excluded: [],
                                       problems: [:], waitingCount: 0, nowPlaying: nil, nextWake: nil, paused: false)
}

/// One scan: read Shazam → engine → store → delivery → snapshot for the UI.
public actor ScanCycle {
    private let source: any TagSource
    private let store: StateStore
    private let delivery: Delivery
    private let time: any TimeSource

    public init(source: any TagSource, store: StateStore, delivery: Delivery, time: any TimeSource) {
        self.source = source
        self.store = store
        self.delivery = delivery
        self.time = time
    }

    public func run(accounts: [Account], scrobblers: [AccountID: any Scrobbler],
                    settings: EngineSettings, recentLimit: Int = 20) async -> Snapshot {
        let now = time.now
        for account in accounts where (try? store.cursor(for: account.id)) == nil {
            try? store.setCursor(account.addedAt, for: account.id)
        }
        var cursors = currentCursors(accounts)
        // Read EngineSettings.duplicateWindow of history before the oldest cursor: the engine only creates rows
        // for tags newer than each account's own cursor, the extra history only feeds duplicate detection.
        var since = readSince(cursors, now: now)
        var result = source.read(since: since, recentLimit: recentLimit)

        if result.status == .ok, (try? LegacyMigration.resolvePending(store: store, source: source)) == true {
            cursors = currentCursors(accounts)
            since = readSince(cursors, now: now)
            result = source.read(since: since, recentLimit: recentLimit)
        }

        var requests: [NowPlayingRequest] = []
        var engineWake: Date?
        if result.status == .ok, !cursors.isEmpty {
            try? store.record(result.tagsSince)
            let choices = (try? store.choices()) ?? (excluded: [], forced: [])
            let output = ScrobbleEngine.evaluate(EngineInput(
                tags: result.tagsSince, now: now, settings: settings, accounts: cursors,
                states: (try? store.states(since: since)) ?? [:],
                excluded: choices.excluded, forced: choices.forced,
                lastNowPlaying: (try? store.lastNowPlaying()) ?? [:]))
            try? store.apply(output.transitions, now: now)
            requests = output.nowPlaying
            engineWake = output.nextWake
        }

        let report = await delivery.run(scrobblers: scrobblers, nowPlaying: requests, paused: settings.paused)

        let states = (try? store.states(for: result.recent.map(\.key))) ?? [:]
        let nowPlaying = result.recent.first.flatMap { tag -> NowPlayingInfo? in
            for state in (states[tag.key] ?? [:]).values {
                if case let .nowPlaying(deadline) = state, deadline > now { return NowPlayingInfo(tag: tag, deadline: deadline) }
            }
            return nil
        }
        var problems = (try? store.heldProblems()) ?? [:]
        problems.merge(report.problems) { _, new in new }

        return Snapshot(
            libraryStatus: result.status, recent: result.recent, states: states,
            excluded: (try? store.choices().excluded) ?? [], problems: problems,
            waitingCount: (try? store.waitingCount()) ?? 0, nowPlaying: nowPlaying,
            nextWake: [engineWake, report.nextWake].compactMap { $0 }.min(), paused: settings.paused)
    }

    private func readSince(_ cursors: [AccountCursor], now: Date) -> Date {
        (cursors.map(\.since).min() ?? now).addingTimeInterval(-EngineSettings.duplicateWindow)
    }

    private func currentCursors(_ accounts: [Account]) -> [AccountCursor] {
        accounts.compactMap { account in
            (try? store.cursor(for: account.id)).map { AccountCursor(id: account.id, since: $0) }
        }
    }
}
