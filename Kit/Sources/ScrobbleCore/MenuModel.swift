import Foundation

public enum AggregateStatus: Equatable, Sendable {
    case none, done, partial, pending, skipped
}

public struct AccountLine: Equatable, Sendable {
    public var account: Account
    /// `nil` when the tag predates the account.
    public var state: DeliveryState?

    public init(account: Account, state: DeliveryState?) { self.account = account; self.state = state }
}

public struct SongRow: Equatable, Sendable {
    public var key: TagKey
    public var track: Track
    public var date: Date
    public var aggregate: AggregateStatus
    public var lines: [AccountLine]
    public var isExcluded: Bool

    public init(key: TagKey, track: Track, date: Date, aggregate: AggregateStatus, lines: [AccountLine],
                isExcluded: Bool) {
        self.key = key; self.track = track; self.date = date; self.aggregate = aggregate
        self.lines = lines; self.isExcluded = isExcluded
    }
}

public struct NowPlayingRow: Equatable, Sendable {
    public var row: SongRow
    public var deadline: Date

    public init(row: SongRow, deadline: Date) { self.row = row; self.deadline = deadline }
}

public struct ProblemRow: Equatable, Sendable {
    public var account: Account
    public var problem: AccountProblem
    public init(account: Account, problem: AccountProblem) { self.account = account; self.problem = problem }
}

public enum LibraryNotice: Equatable, Sendable {
    case waitingForShazam, notInstalled, accessDenied
    case unsupported(String)
    case unreadable(String)
}

public struct MenuContent: Equatable, Sendable {
    public var nowPlaying: NowPlayingRow?
    public var recent: [SongRow]
    public var problems: [ProblemRow]
    public var library: LibraryNotice?
    public var paused: Bool
    public var waitingCount: Int

    public init(nowPlaying: NowPlayingRow?, recent: [SongRow], problems: [ProblemRow], library: LibraryNotice?,
                paused: Bool, waitingCount: Int) {
        self.nowPlaying = nowPlaying; self.recent = recent; self.problems = problems
        self.library = library; self.paused = paused; self.waitingCount = waitingCount
    }
}

public enum MenuModel {
    public static let recentSlots = 20
    public static let problemSlots = 5

    public static func content(snapshot: Snapshot, accounts: [Account]) -> MenuContent {
        func row(_ tag: ShazamTag) -> SongRow {
            let lines = accounts.map { AccountLine(account: $0, state: snapshot.states[tag.key]?[$0.id]) }
            return SongRow(key: tag.key, track: tag.track, date: tag.date, aggregate: aggregate(lines.map(\.state)),
                           lines: lines, isExcluded: snapshot.excluded.contains(tag.key))
        }
        let nowPlaying = snapshot.nowPlaying.map { NowPlayingRow(row: row($0.tag), deadline: $0.deadline) }
        let recent = snapshot.recent.filter { $0.key != nowPlaying?.row.key }.prefix(recentSlots).map(row)
        let problems = accounts.compactMap { account in
            snapshot.problems[account.id].map { ProblemRow(account: account, problem: $0) }
        }

        return MenuContent(nowPlaying: nowPlaying, recent: Array(recent), problems: Array(problems.prefix(problemSlots)),
                           library: notice(for: snapshot.libraryStatus), paused: snapshot.paused,
                           waitingCount: snapshot.waitingCount)
    }

    public static func aggregate(_ states: [DeliveryState?]) -> AggregateStatus {
        let present = states.compactMap { $0 }
        guard !present.isEmpty else { return .none }
        let scrobbled = present.filter { if case .scrobbled = $0 { true } else { false } }.count
        if scrobbled == present.count { return .done }
        if scrobbled > 0 { return .partial }
        if present.allSatisfy(\.isFinal) { return .skipped }
        return .pending
    }

    /// Indices whose content differs; the menu updates only those items (§6.2).
    public static func changedSlots<T: Equatable>(old: [T?], new: [T?]) -> [Int] {
        (0..<max(old.count, new.count)).filter { index in
            (index < old.count ? old[index] : nil) != (index < new.count ? new[index] : nil)
        }
    }

    public static func countdown(to deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func notice(for status: LibraryStatus) -> LibraryNotice? {
        switch status {
        case .ok: nil
        case .noLibraryYet: .waitingForShazam
        case .notInstalled: .notInstalled
        case .accessDenied: .accessDenied
        case let .unsupportedSchema(detail): .unsupported(detail)
        case let .unreadable(detail): .unreadable(detail)
        }
    }
}
