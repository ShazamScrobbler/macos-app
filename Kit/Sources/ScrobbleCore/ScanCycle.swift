import Foundation
import os

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

    typealias StatesReader = @Sendable (StateStore, Date) throws -> [TagKey: [AccountID: DeliveryState]]

    private let statesReader: StatesReader
    private let log = Logger(subsystem: "ShazamScrobbler", category: "engine")

    public init(source: any TagSource, store: StateStore, delivery: Delivery, time: any TimeSource) {
        self.init(source: source, store: store, delivery: delivery, time: time,
                  statesReader: { try $0.states(since: $1) })
    }

    /// `statesReader` exists so tests can simulate a failing store read.
    init(source: any TagSource, store: StateStore, delivery: Delivery, time: any TimeSource,
         statesReader: @escaping StatesReader) {
        self.source = source
        self.store = store
        self.delivery = delivery
        self.time = time
        self.statesReader = statesReader
    }

    /// Callers must not overlap runs (the app serializes through `RescanGate`): `Delivery.run` must not run concurrently.
    public func run(accounts: [Account], scrobblers: [AccountID: any Scrobbler],
                    settings: EngineSettings, recentLimit: Int = 20) async -> Snapshot {
        let now = time.now
        var inputsOK = true
        var cursors: [AccountCursor] = []
        for account in accounts {
            do {
                if let cursor = try store.cursor(for: account.id) {
                    cursors.append(AccountCursor(id: account.id, since: cursor))
                } else {
                    try store.setCursor(account.addedAt, for: account.id)
                    cursors.append(AccountCursor(id: account.id, since: account.addedAt))
                }
            } catch {
                inputsOK = false
                log.error("cursor read failed for \(account.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        // Read EngineSettings.duplicateWindow of history before the oldest cursor: the engine only creates rows
        // for tags newer than each account's own cursor, the extra history only feeds duplicate detection.
        var since = readSince(cursors, now: now)
        var result = source.read(since: since, recentLimit: recentLimit)

        if inputsOK, result.status == .ok, (try? LegacyMigration.resolvePending(store: store, source: source)) == true {
            cursors = currentCursors(accounts)
            since = readSince(cursors, now: now)
            result = source.read(since: since, recentLimit: recentLimit)
        }

        var requests: [NowPlayingRequest] = []
        var engineWake: Date?
        if inputsOK, result.status == .ok, !cursors.isEmpty {
            do {
                // All reads first: a failed read must skip the engine, never feed it empty state.
                let states = try statesReader(store, since)
                let choices = try store.choices()
                let lastNowPlaying = try store.lastNowPlaying()
                try store.record(result.tagsSince)
                let output = ScrobbleEngine.evaluate(EngineInput(
                    tags: result.tagsSince, now: now, settings: settings, accounts: cursors,
                    states: states, excluded: choices.excluded, forced: choices.forced,
                    lastNowPlaying: lastNowPlaying))
                try store.apply(output.transitions, now: now)
                requests = output.nowPlaying
                engineWake = output.nextWake
            } catch {
                log.error("engine step skipped: \(error.localizedDescription, privacy: .public)")
            }
        }

        let report = await delivery.run(scrobblers: scrobblers, nowPlaying: requests, paused: settings.paused)

        let states = (try? store.states(for: result.recent.map(\.key))) ?? [:]
        // Newest recent tag with a live now-playing state (an Auto-Shazam re-tag is newer but a duplicate).
        var nowPlaying: NowPlayingInfo?
        for tag in result.recent {
            let deadlines = (states[tag.key] ?? [:]).values.compactMap { state -> Date? in
                if case let .nowPlaying(deadline) = state, deadline > now { return deadline }
                return nil
            }
            if let deadline = deadlines.min() { nowPlaying = NowPlayingInfo(tag: tag, deadline: deadline); break }
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
