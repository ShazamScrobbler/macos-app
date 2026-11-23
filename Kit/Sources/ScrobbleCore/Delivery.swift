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

    public init(store: StateStore, time: any TimeSource,
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.store = store
        self.time = time
        self.random = random
    }

    public func run(scrobblers: [AccountID: any Scrobbler], nowPlaying: [NowPlayingRequest],
                    paused: Bool) async -> DeliveryReport {
        var report = DeliveryReport()
        if !paused {
            for (account, scrobbler) in scrobblers.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                if let problem = (try? store.heldProblems())?[account] {
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
        report.nextWake = try? store.nextRetryDate()
        return report
    }

    private func sendNowPlaying(_ requests: [NowPlayingRequest], account: AccountID, scrobbler: any Scrobbler,
                                report: inout DeliveryReport) async {
        for request in requests {
            do {
                if !request.isRefresh {
                    let ours = (try? store.lastNowPlaying())?[account].flatMap { try? store.track(for: $0.key) }
                    if try await scrobbler.isOtherPlayerActive(excluding: ours) {
                        log.info("Another player is active for \(account.rawValue, privacy: .public); skipping tag")
                        try? store.set(.skipped(.otherPlayer), key: request.tag.key, account: account, now: time.now)
                        continue
                    }
                }
                try await scrobbler.nowPlaying(request.tag.track)
                try? store.setNowPlaying(NowPlayingRecord(key: request.tag.key, sentAt: time.now), for: account)
            } catch {
                let scrobbleError = error.asScrobbleError
                if let problem = DeliveryPolicy.problem(for: scrobbleError) {
                    report.problems[account] = problem
                    try? store.hold(account: account, problem: problem, now: time.now)
                    return
                }
                log.notice("Now playing failed for \(account.rawValue, privacy: .public): \(String(describing: scrobbleError), privacy: .public)")
            }
        }
    }

    private func sendPending(account: AccountID, scrobbler: any Scrobbler, report: inout DeliveryReport) async {
        while true {
            guard let items = try? store.pending(account: account, dueBy: time.now, limit: scrobbler.maxBatchSize),
                  !items.isEmpty else { return }
            let now = time.now
            var sendable: [PendingItem] = []
            for item in items {
                if let maxAge = scrobbler.maxScrobbleAge, now.timeIntervalSince(item.date) > maxAge {
                    try? store.set(.ignored("Too old for this service (over 14 days)"), key: item.key, account: account, now: now)
                } else {
                    sendable.append(item)
                }
            }
            guard !sendable.isEmpty else { continue }
            if await send(sendable, account: account, scrobbler: scrobbler, report: &report) == .stop { return }
        }
    }

    private enum Outcome { case proceed, stop }

    private func send(_ items: [PendingItem], account: AccountID, scrobbler: any Scrobbler,
                      report: inout DeliveryReport) async -> Outcome {
        let now = time.now
        do {
            let results = try await scrobbler.scrobble(items.map { ScrobbleItem(key: $0.key, track: $0.track, date: $0.date) })
            for (item, result) in zip(items, results) {
                switch result {
                case .accepted:
                    try? store.set(.scrobbled(at: now), key: item.key, account: account, now: now)
                    report.scrobbled += 1
                case let .ignored(reason):
                    try? store.set(.ignored(reason), key: item.key, account: account, now: now)
                case .dailyLimit:
                    let attempt: Int
                    if case let .retry(previous, _) = item.state { attempt = previous + 1 } else { attempt = 1 }
                    try? store.set(.retry(attempt: attempt, nextAt: Backoff.nextUTCMidnight(after: now)),
                                   key: item.key, account: account, now: now)
                }
            }
            return .proceed
        } catch {
            let scrobbleError = error.asScrobbleError
            if let problem = DeliveryPolicy.problem(for: scrobbleError) {
                report.problems[account] = problem
                try? store.hold(account: account, problem: problem, now: now)
                return .stop
            }
            if case .permanent = scrobbleError, items.count > 1 {
                for item in items {
                    if await send([item], account: account, scrobbler: scrobbler, report: &report) == .stop { return .stop }
                }
                return .proceed
            }
            for item in items {
                try? store.set(DeliveryPolicy.state(after: scrobbleError, previous: item.state, now: now, random: random()),
                               key: item.key, account: account, now: now)
            }
            if case .permanent = scrobbleError { return .proceed }
            log.notice("Delivery paused for \(account.rawValue, privacy: .public): \(String(describing: scrobbleError), privacy: .public)")
            return .stop
        }
    }
}
