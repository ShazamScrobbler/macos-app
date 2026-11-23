import Foundation

public struct Track: Hashable, Sendable, Codable {
    public var artist: String
    public var title: String
    public var album: String?

    public init(artist: String, title: String, album: String? = nil) {
        self.artist = artist
        self.title = title
        self.album = album
    }

    /// Identity for "is this the same song" (duplicate detection, other-player check).
    public var matchKey: String { "\(artist.normalizedForMatch)\u{1F}\(title.normalizedForMatch)" }
}

extension String {
    var normalizedForMatch: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

public struct ShazamTag: Hashable, Sendable {
    public var pk: Int64
    public var date: Date
    public var track: Track

    public init(pk: Int64, date: Date, track: Track) {
        self.pk = pk
        self.date = date
        self.track = track
    }

    public var key: TagKey { TagKey(date: date, track: track) }
}

/// Stable identity of a tag that survives Shazam recreating its database (row ids restart, dates don't).
public struct TagKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(date: Date, track: Track) {
        rawValue = "\(Int64(date.timeIntervalSince1970.rounded(.down)))\u{1F}\(track.artist)\u{1F}\(track.title)"
    }

    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue.replacingOccurrences(of: "\u{1F}", with: " | ") }
}
