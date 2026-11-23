import Foundation

public enum LegacyMigration {
    public static let doneKey = "migratedToV2"
    private static let legacyKeys = ["session", "username", "lastScrobble", "notToScrobble", "scrobbling"]

    /// Step 1, at launch. Returns the created Last.fm account, if 1.x was signed in.
    @discardableResult
    public static func migrateDefaults(defaults: UserDefaults, accounts: AccountStore, settings: SettingsStore,
                                       store: StateStore, now: Date) throws -> Account? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        var created: Account?
        if let session = defaults.string(forKey: "session"), !session.isEmpty {
            let account = Account(id: .new(), preset: .lastfm, username: defaults.string(forKey: "username") ?? "",
                                  apiURL: ServicePreset.lastfm.defaultAPIURL!, webAuthURL: ServicePreset.lastfm.defaultWebAuthURL,
                                  keyMode: .builtIn, addedAt: now)
            accounts.upsert(account)
            try accounts.setSecret(session, .sessionKey, for: account.id)
            try store.setCursor(now, for: account.id)
            try store.setMeta("legacy.account", account.id.rawValue)
            if let pk = defaults.object(forKey: "lastScrobble") as? Int {
                try store.setMeta("legacy.lastScrobblePK", String(pk))
            }
            created = account
        }
        if let excluded = defaults.array(forKey: "notToScrobble") as? [Int], !excluded.isEmpty {
            try store.setMeta("legacy.notToScrobble", excluded.map(String.init).joined(separator: ","))
        }
        if defaults.object(forKey: "scrobbling") != nil, defaults.integer(forKey: "scrobbling") == 0 {
            settings.engineSettings = EngineSettings(paused: true, pauseMode: .keep,
                                                     minPlayTime: settings.engineSettings.minPlayTime)
        }
        legacyKeys.forEach(defaults.removeObject(forKey:))
        defaults.set(true, forKey: doneKey)
        return created
    }

    /// Step 2, on the first scan that can read Shazam. Returns true if it changed anything.
    public static func resolvePending(store: StateStore, source: any TagSource) throws -> Bool {
        let accountID = try store.meta("legacy.account").map(AccountID.init(rawValue:))
        let lastPK = try store.meta("legacy.lastScrobblePK").flatMap(Int64.init)
        let excludedPKs = try store.meta("legacy.notToScrobble")?.split(separator: ",").compactMap { Int64($0) } ?? []
        guard accountID != nil || lastPK != nil || !excludedPKs.isEmpty else { return false }

        let found = source.tags(withPKs: excludedPKs + (lastPK.map { [$0] } ?? []))
        if let accountID, let lastPK, let tag = found[lastPK] {
            try store.setCursor(tag.date, for: accountID)
        }
        for pk in excludedPKs {
            if let tag = found[pk] { try store.setChoice(.exclude, for: tag.key) }
        }
        for key in ["legacy.account", "legacy.lastScrobblePK", "legacy.notToScrobble"] { try store.setMeta(key, nil) }
        return true
    }
}
