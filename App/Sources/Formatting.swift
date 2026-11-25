import AppKit
import ScrobbleCore

enum Formatting {
    static let maxTitleLength = 60

    static func songTitle(_ track: Track) -> String { "\(track.artist) – \(track.title)" }

    static func truncateMiddle(_ text: String, max: Int = maxTitleLength) -> String {
        guard text.count > max, max > 1 else { return text }
        let head = (max - 1) / 2, tail = max - 1 - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    static func serviceName(_ preset: ServicePreset) -> String {
        switch preset {
        case .lastfm: String(localized: "Last.fm")
        case .librefm: String(localized: "Libre.fm")
        case .listenbrainz: String(localized: "ListenBrainz")
        case .customAudioscrobbler: String(localized: "Custom (Last.fm-compatible)")
        case .customListenBrainz: String(localized: "Custom (ListenBrainz-compatible)")
        }
    }

    static func accountName(_ account: Account) -> String {
        switch account.preset {
        case .customAudioscrobbler, .customListenBrainz:
            "\(account.username) @ \(account.apiURL.host ?? account.apiURL.absoluteString)"
        default:
            "\(serviceName(account.preset)) (\(account.username))"
        }
    }

    static func state(_ state: DeliveryState?) -> String {
        guard let state else { return String(localized: "Not sent (added after this tag)") }
        switch state {
        case .waiting: return String(localized: "Waiting")
        case .nowPlaying: return String(localized: "Now playing")
        case let .scrobbled(at): return String(localized: "Scrobbled \(time(at))")
        case .tooShort: return String(localized: "Not played long enough")
        case .skipped(.paused): return String(localized: "Skipped while paused")
        case .skipped(.user): return String(localized: "Not scrobbled (your choice)")
        case .skipped(.otherPlayer): return String(localized: "Skipped: another player was active")
        case .skipped(.duplicate): return String(localized: "Repeat of the previous tag")
        case let .ignored(reason): return String(localized: "Not accepted: \(reason)")
        case .held(.signedOut): return String(localized: "On hold: signed out")
        case .held(.keyUnusable): return String(localized: "On hold: API key not working")
        case let .retry(_, nextAt): return String(localized: "Retrying at \(time(nextAt))")
        }
    }

    static func problem(_ row: ProblemRow) -> String {
        let name = accountName(row.account)
        switch row.problem {
        case .signedOut: return String(localized: "\(name): signed out")
        case .keyUnusable where row.account.keyMode == .builtIn:
            return String(localized: "\(name): key not working. Last.fm may require Pro for this key")
        case .keyUnusable: return String(localized: "\(name): API key not working")
        }
    }

    static func library(_ notice: LibraryNotice) -> String {
        switch notice {
        case .waitingForShazam: String(localized: "Waiting for Shazam's first tag")
        case .notInstalled: String(localized: "Shazam isn't installed: Get Shazam…")
        case .accessDenied: String(localized: "Can't read Shazam: Set Up Access…")
        case .unsupported: String(localized: "This Shazam version isn't supported yet")
        case .unreadable: String(localized: "Can't read Shazam's library right now")
        }
    }

    /// Self-hosted servers on the LAN need macOS's Local Network permission (macOS 15+, §12b).
    static func isLocalNetwork(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }

    static func symbol(_ status: AggregateStatus) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .pending: "clock"
        case .skipped: "nosign"
        case .none: "music.note"
        }
    }

    static func symbolDescription(_ status: AggregateStatus) -> String {
        switch status {
        case .done: String(localized: "Scrobbled")
        case .partial: String(localized: "Scrobbled to some accounts")
        case .pending: String(localized: "Waiting")
        case .skipped: String(localized: "Not scrobbled")
        case .none: String(localized: "No accounts")
        }
    }
}

extension NSApplication {
    /// Agent apps must activate before showing a window, or it opens behind the frontmost app.
    func activateApp() {
        if #available(macOS 14.0, *) { activate() } else { activate(ignoringOtherApps: true) }
    }
}
