import Foundation
import os

public struct DeliveryReport: Sendable, Equatable {
    public var problems: [AccountID: AccountProblem] = [:]
    public var scrobbled = 0
    public var nextWake: Date?
    public init() {}
}

/// Sends now-playing updates and pending scrobbles, one account at a time (spec §7).
public actor Delivery {
    private let store: StateStore
    private let time: any TimeSource
    private let random: @Sendable () -> Double
    private let log = Logger(subsystem: "ShazamScrobbler", category: "delivery")
    /// Accounts whose first-time now playing failed transiently: not retried before this date. Refreshes are exempt.
    private var nowPlayingRetryAfter: [AccountID: Date] = [:]
    private static let nowPlayingBackoff: TimeInterval = 90   // minimum; a longer server retryAfter wins

    typealias HeldProblemsReader = @Sendable (StateStore) throws -> [AccountID: AccountProblem]
    private let heldProblemsReader: HeldProblemsReader

    public init(store: StateStore, time: any TimeSource,
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.init(store: store, time: time, random: random, heldProblemsReader: { try $0.heldProblems() })
    }

    /// `heldProblemsReader` exists so tests can simulate a failing store read.
    init(store: StateStore, time: any TimeSource, random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
         heldProblemsReader: @escaping HeldProblemsReader) {
        self.store = store
        self.time = time
        self.random = random
        self.heldProblemsReader = heldProblemsReader
    }

    /// Callers must not run this concurrently (ScanCycle serializes runs via RescanGate).
    /// `nextWake` is nil when paused; otherwise the earliest retry among `scrobblers`' accounts, at least 30 s away.
    public func run(scrobblers: [AccountID: any Scrobbler], nowPlaying: [NowPlayingRequest],
                    paused: Bool) async -> DeliveryReport {
        var report = DeliveryReport()
        if !paused {
            // Unreadable held problems must not look like "no problems": send nothing this run.
            let held: [AccountID: AccountProblem]
            do { held = try heldProblemsReader(store) } catch {
                log.error("held problems read failed; sending nothing this run: \(error.localizedDescription, privacy: .private)")
                return report
            }
            for (account, scrobbler) in scrobblers.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                if let problem = held[account] {
                    report.problems[account] = problem
                    continue
                }
                await sendNowPlaying(nowPlaying.filter { $0.account == account }, account: account,
                                     scrobbler: scrobbler, report: &report)
                guard report.problems[account] == nil else { continue }
                await sendPending(account: account, scrobbler: scrobbler, report: &report)
                try? store.advanceCursor(for: account)
            }
        }
        if !paused, let next = (try? store.nextRetryDate(accounts: Array(scrobblers.keys))) ?? nil {
            report.nextWake = max(next, time.now + 30)
        }
        return report
    }

    private func sendNowPlaying(_ requests: [NowPlayingRequest], account: AccountID, scrobbler: any Scrobbler,
                                report: inout DeliveryReport) async {
        for request in requests {
            if !request.isRefresh, let after = nowPlayingRetryAfter[account], time.now < after { continue }
            do {
                if !request.isRefresh {
                    let ours = (try? store.lastNowPlaying())?[account].flatMap { try? store.track(for: $0.key) }
                    if try await scrobbler.isOtherPlayerActive(excluding: ours) {
                        log.info("Another player is active for \(account.rawValue, privacy: .public); skipping tag")
                        _ = try? store.transition(key: request.tag.key, account: account, fromKinds: ["nowPlaying"],
                                              to: .skipped(.otherPlayer), now: time.now)
                        continue
                    }
                }
                try await scrobbler.nowPlaying(request.tag.track)
                try? store.setNowPlaying(NowPlayingRecord(key: request.tag.key, sentAt: time.now), for: account)
                nowPlayingRetryAfter[account] = nil
            } catch {
                let scrobbleError = error.asScrobbleError
                if let problem = DeliveryPolicy.problem(for: scrobbleError) {
                    report.problems[account] = problem
                    try? store.hold(account: account, problem: problem, now: time.now)
                    return
                }
                switch scrobbleError {
                case .transient, .rateLimited:
                    if !request.isRefresh {
                        var delay = Self.nowPlayingBackoff
                        if case let .rateLimited(retryAfter) = scrobbleError { delay = max(delay, retryAfter ?? 0) }
                        nowPlayingRetryAfter[account] = time.now.addingTimeInterval(delay)
                    }
                default: break
                }
                log.notice("Now playing failed for \(account.rawValue, privacy: .public): \(scrobbleError.logSummary, privacy: .public) (\(String(describing: scrobbleError), privacy: .private))")
            }
        }
    }

    /// Upper bound on batches per account per run; guards against a loop that makes no progress.
    private static let maxBatchesPerRun = 1000

    private func sendPending(account: AccountID, scrobbler: any Scrobbler, report: inout DeliveryReport) async {
        let pendingKinds: Set<String> = ["waiting", "retry"]
        for _ in 0..<Self.maxBatchesPerRun {
            do {
                let items = try store.pending(account: account, dueBy: time.now, limit: scrobbler.maxBatchSize)
                if items.isEmpty { return }
                let now = time.now
                var sendable: [PendingItem] = []
                for item in items {
                    if let maxAge = scrobbler.maxScrobbleAge, now.timeIntervalSince(item.date) > maxAge {
                        try store.transition(key: item.key, account: account, fromKinds: pendingKinds,
                                             to: .ignored("Too old for this service (over 14 days)"), now: now)
                    } else {
                        sendable.append(item)
                    }
                }
                if sendable.isEmpty { continue }
                if await send(sendable, account: account, scrobbler: scrobbler, report: &report) == .stop { return }
            } catch {
                log.error("Store error for \(account.rawValue, privacy: .public); stopping account: \(String(describing: error), privacy: .private)")
                return
            }
        }
        log.error("Batch limit reached for \(account.rawValue, privacy: .public)")
    }

    private enum Outcome { case proceed, stop }

    private func send(_ items: [PendingItem], account: AccountID, scrobbler: any Scrobbler,
                      report: inout DeliveryReport) async -> Outcome {
        let pendingKinds: Set<String> = ["waiting", "retry"]
        let results: [ScrobbleItemResult]
        var failure: ScrobbleError?
        do {
            let sent = try await scrobbler.scrobble(items.map { ScrobbleItem(key: $0.key, track: $0.track, date: $0.date) })
            if sent.count == items.count {
                results = sent
            } else {
                results = []
                failure = .transient("Unexpected result count")
            }
        } catch {
            results = []
            failure = error.asScrobbleError
        }
        let now = time.now
        do {
            if let scrobbleError = failure {
                if let problem = DeliveryPolicy.problem(for: scrobbleError) {
                    report.problems[account] = problem
                    try store.hold(account: account, problem: problem, now: now)
                    return .stop
                }
                if case .permanent = scrobbleError, items.count > 1 {
                    for item in items {
                        if await send([item], account: account, scrobbler: scrobbler, report: &report) == .stop { return .stop }
                    }
                    return .proceed
                }
                for item in items {
                    try store.transition(key: item.key, account: account, fromKinds: pendingKinds,
                                         to: DeliveryPolicy.state(after: scrobbleError, previous: item.state, now: now, random: random()),
                                         now: now)
                }
                if case .permanent = scrobbleError { return .proceed }
                log.notice("Delivery paused for \(account.rawValue, privacy: .public): \(scrobbleError.logSummary, privacy: .public) (\(String(describing: scrobbleError), privacy: .private))")
                return .stop
            }
            var hitDailyLimit = false
            for (item, result) in zip(items, results) {
                switch result {
                case .accepted:
                    if try store.transition(key: item.key, account: account, fromKinds: pendingKinds, to: .scrobbled(at: now), now: now) {
                        report.scrobbled += 1
                    }
                case let .ignored(reason):
                    try store.transition(key: item.key, account: account, fromKinds: pendingKinds, to: .ignored(reason), now: now)
                case .dailyLimit:
                    hitDailyLimit = true
                    let attempt: Int
                    if case let .retry(previous, _) = item.state { attempt = previous + 1 } else { attempt = 1 }
                    try store.transition(key: item.key, account: account, fromKinds: pendingKinds,
                                         to: .retry(attempt: attempt, nextAt: Backoff.nextUTCMidnight(after: now)), now: now)
                }
            }
            return hitDailyLimit ? .stop : .proceed
        } catch {
            log.error("Store error for \(account.rawValue, privacy: .public); stopping account: \(String(describing: error), privacy: .private)")
            return .stop
        }
    }
}
