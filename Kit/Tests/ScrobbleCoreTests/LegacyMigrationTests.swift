import Foundation
import Testing
import TestSupport
@testable import ScrobbleCore

@Suite struct LegacyMigrationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func legacyDefaults(scrobbling: Int = 1) -> UserDefaults {
        let name = "legacy.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set("SESSIONKEY", forKey: "session")
        d.set("steph", forKey: "username")
        d.set(11938, forKey: "lastScrobble")
        d.set([3, 4, 72], forKey: "notToScrobble")
        d.set(scrobbling, forKey: "scrobbling")
        return d
    }

    @Test func convertsDefaultsAndRemovesOldKeys() throws {
        let defaults = legacyDefaults(scrobbling: 0)
        let secrets = InMemorySecretStore()
        let accounts = AccountStore(defaults: defaults, secrets: secrets)
        let settings = SettingsStore(defaults: defaults)
        let store = try StateStore(url: nil)

        let account = try #require(try LegacyMigration.migrateDefaults(
            defaults: defaults, accounts: accounts, settings: settings, store: store, now: now))
        #expect(account.preset == .lastfm && account.username == "steph" && account.keyMode == .builtIn)
        #expect(accounts.load() == [account])
        #expect(accounts.secret(.sessionKey, for: account.id) == "SESSIONKEY")
        #expect(try store.cursor(for: account.id) == now)
        #expect(settings.engineSettings.paused && settings.engineSettings.pauseMode == .keep)
        for key in ["session", "username", "lastScrobble", "notToScrobble", "scrobbling"] {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(try LegacyMigration.migrateDefaults(defaults: defaults, accounts: accounts, settings: settings,
                                                    store: store, now: now) == nil)
        #expect(accounts.load().count == 1)
    }

    @Test func enabledScrobblingStaysUnpaused() throws {
        let defaults = legacyDefaults(scrobbling: 1)
        let settings = SettingsStore(defaults: defaults)
        _ = try LegacyMigration.migrateDefaults(defaults: defaults, accounts: AccountStore(defaults: defaults, secrets: InMemorySecretStore()),
                                                settings: settings, store: try StateStore(url: nil), now: now)
        #expect(settings.engineSettings.paused == false)
    }

    @Test func resolvesRowIdsOnceLibraryIsReadable() throws {
        let defaults = legacyDefaults()
        let accounts = AccountStore(defaults: defaults, secrets: InMemorySecretStore())
        let store = try StateStore(url: nil)
        let account = try #require(try LegacyMigration.migrateDefaults(
            defaults: defaults, accounts: accounts, settings: SettingsStore(defaults: defaults), store: store, now: now))
        let last = ShazamTag(pk: 11938, date: now - 3600, track: Track(artist: "A", title: "Last"))
        let excluded = ShazamTag(pk: 72, date: now - 9000, track: Track(artist: "B", title: "No"))
        let source = FakeTagSource(byPK: [11938: last, 72: excluded])

        #expect(try LegacyMigration.resolvePending(store: store, source: source) == true)
        #expect(try store.cursor(for: account.id) == last.date)
        #expect(try store.choices().excluded == [excluded.key])
        #expect(try LegacyMigration.resolvePending(store: store, source: source) == false)
    }

    @Test func missingRowsKeepCursorAtNow() throws {   // Shazam DB recreated since 1.x
        let defaults = legacyDefaults()
        let accounts = AccountStore(defaults: defaults, secrets: InMemorySecretStore())
        let store = try StateStore(url: nil)
        let account = try #require(try LegacyMigration.migrateDefaults(
            defaults: defaults, accounts: accounts, settings: SettingsStore(defaults: defaults), store: store, now: now))
        #expect(try LegacyMigration.resolvePending(store: store, source: FakeTagSource()) == true)
        #expect(try store.cursor(for: account.id) == now)
    }

    @Test func freshInstallDoesNothing() throws {
        let name = "fresh.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let store = try StateStore(url: nil)
        #expect(try LegacyMigration.migrateDefaults(defaults: d, accounts: AccountStore(defaults: d, secrets: InMemorySecretStore()),
                                                    settings: SettingsStore(defaults: d), store: store, now: now) == nil)
        #expect(d.bool(forKey: LegacyMigration.doneKey))
        #expect(try LegacyMigration.resolvePending(store: store, source: FakeTagSource()) == false)
    }
}
