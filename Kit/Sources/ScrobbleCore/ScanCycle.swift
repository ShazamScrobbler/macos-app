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
    /// `retryNow`: the scan was triggered by a reconnect, a wake or a fixed account, so transient retries are sent now
    /// instead of waiting for their backoff (spec §7). A new tag recorded by this scan has the same effect.
    public func run(accounts: [Account], scrobblers: [AccountID: any Scrobbler],
                    settings: EngineSettings, recentLimit: Int = 20, retryNow: Bool = false) async -> Snapshot {
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
                log.error("cursor read failed for \(account.id.rawValue, privacy: .public): \(error.localizedDescription, privacy: .private)")
            }
        }
        // Each deliverable account (a scrobbler, no held problem) is evaluated against its own read window:
        // `cursor - EngineSettings.duplicateWindow`, the extra history only feeds duplicate detection. Accounts with
        // the same cursor share one read. A stuck account with an old cursor therefore can't push the newest tags
        // beyond the reader's cap for everyone else, and a held or unusable account (which keeps its cursor, so its
        // backlog is evaluated once released) never drives a window at all.
        var held: [AccountID: AccountProblem] = [:]
        do { held = try store.heldProblems() } catch {
            inputsOK = false
            log.error("held problems read failed: \(error.localizedDescription, privacy: .private)")
        }
        let deliverable = Set(scrobblers.keys).subtracting(held.keys)
        var choices: (excluded: Set<TagKey>, forced: Set<TagKey>) = ([], [])
        do { choices = try store.choices() } catch {
            inputsOK = false
            log.error("choices read failed: \(error.localizedDescription, privacy: .private)")
        }

        var reads = readWindows(cursors.filter { deliverable.contains($0.id) }, now: now, recentLimit: recentLimit)
        if inputsOK, reads.status == .ok {
            do {
                if try LegacyMigration.resolvePending(store: store, source: source) {
                    reads = readWindows(currentCursors(accounts).filter { deliverable.contains($0.id) }, now: now, recentLimit: recentLimit)
                }
            } catch {
                log.error("legacy migration step failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        var requests: [NowPlayingRequest] = []
        var engineWake: Date?
        var newTag = false
        if inputsOK, reads.status == .ok {
            do {
                let lastNowPlaying = try store.lastNowPlaying()
                for window in reads.windows {
                    // All reads first: a failed read must skip the engine, never feed it empty state.
                    let states = try statesReader(store, window.since)
                    try store.record(window.tags)
                    let output = ScrobbleEngine.evaluate(EngineInput(
                        tags: window.tags, now: now, settings: settings, accounts: window.accounts,
                        states: states, excluded: choices.excluded, forced: choices.forced,
                        lastNowPlaying: lastNowPlaying))
                    try store.apply(output.transitions, now: now)
                    // A row for a tag/account pair seen for the first time: a new tag was detected.
                    if output.transitions.contains(where: { states[$0.key]?[$0.account] == nil }) { newTag = true }
                    requests += output.nowPlaying
                    engineWake = [engineWake, output.nextWake].compactMap { $0 }.min()
                }
            } catch {
                log.error("engine step skipped: \(error.localizedDescription, privacy: .private)")
            }
        }
        let result = reads.result

        let retryDue = retryNow || newTag
        if retryDue {
            do { try store.makeTransientRetriesDue(now: now) } catch {
                log.error("making retries due failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        let report = await delivery.run(scrobblers: scrobblers, nowPlaying: requests, paused: settings.paused,
                                        retryNow: retryDue)

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
            excluded: choices.excluded, problems: problems,
            waitingCount: (try? store.waitingCount()) ?? 0, nowPlaying: nowPlaying,
            nextWake: [engineWake, report.nextWake].compactMap { $0 }.min(), paused: settings.paused)
    }

    private struct ReadWindow {
        var since: Date
        var accounts: [AccountCursor]
        var tags: [ShazamTag]
    }

    /// One `source.read` per distinct cursor. `status` is the first non-ok status (any failed read skips the engine);
    /// `result` carries the `recent` list, read only in the newest window (a failed read's result wins).
    private func readWindows(_ cursors: [AccountCursor], now: Date, recentLimit: Int)
        -> (windows: [ReadWindow], status: LibraryStatus, result: TagSourceResult) {
        let grouped = Dictionary(grouping: cursors, by: \.since)
        let sinces = grouped.keys.sorted()
        guard !sinces.isEmpty else {
            let result = source.read(since: now.addingTimeInterval(-EngineSettings.duplicateWindow), recentLimit: recentLimit)
            return ([], result.status, result)
        }
        var windows: [ReadWindow] = []
        var newest: TagSourceResult?
        var status = LibraryStatus.ok
        for (index, cursor) in sinces.enumerated() {
            let since = cursor.addingTimeInterval(-EngineSettings.duplicateWindow)
            // `recent` is the same newest tags in every read, so only the newest window (last: `sinces` is ascending) fetches it.
            let isNewest = index == sinces.count - 1
            let result = source.read(since: since, recentLimit: isNewest ? recentLimit : 0)
            // Any non-ok read wins (first one kept); otherwise the newest window's result carries `recent`.
            if status == .ok {
                if result.status != .ok { status = result.status; newest = result } else if isNewest { newest = result }
            }
            windows.append(ReadWindow(since: since, accounts: grouped[cursor] ?? [], tags: result.tagsSince))
        }
        return (windows, status, newest ?? TagSourceResult(status: status))
    }

    private func currentCursors(_ accounts: [Account]) -> [AccountCursor] {
        accounts.compactMap { account in
            (try? store.cursor(for: account.id)).map { AccountCursor(id: account.id, since: $0) }
        }
    }
}
