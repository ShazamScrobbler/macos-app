import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct StoresTests {
    func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    let account = Account(id: AccountID(rawValue: "acc-1"), preset: .listenbrainz, username: "steph",
                          apiURL: URL(string: "https://api.listenbrainz.org")!, webAuthURL: nil,
                          keyMode: .own, addedAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func accountsRoundTripWithoutSecretsInDefaults() throws {
        let defaults = freshDefaults()
        let secrets = InMemorySecretStore()
        let store = AccountStore(defaults: defaults, secrets: secrets)
        store.upsert(account)
        try store.setSecret("TOKEN", .token, for: account.id)
        #expect(store.load() == [account])
        #expect(store.secret(.token, for: account.id) == "TOKEN")
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: defaults.dictionaryRepresentation().mapValues { "\($0)" }), as: UTF8.self)
        #expect(!raw.contains("TOKEN"))
    }

    @Test func upsertReplacesAndRemoveDeletesSecrets() throws {
        let secrets = InMemorySecretStore()
        let store = AccountStore(defaults: freshDefaults(), secrets: secrets)
        store.upsert(account)
        var renamed = account; renamed.username = "other"
        store.upsert(renamed)
        #expect(store.load() == [renamed])
        try store.setSecret("S", .sessionKey, for: account.id)
        try store.setSecret("K", .apiKey, for: account.id)
        try store.remove(account.id)
        #expect(store.load().isEmpty)
        #expect(store.secret(.sessionKey, for: account.id) == nil)
        #expect(store.secret(.apiKey, for: account.id) == nil)
    }

    @Test func settingsDefaultsAndClamping() {
        let settings = SettingsStore(defaults: freshDefaults())
        #expect(settings.engineSettings == EngineSettings())
        settings.engineSettings = EngineSettings(paused: true, pauseMode: .keep, minPlayTime: 5)
        #expect(settings.engineSettings == EngineSettings(paused: true, pauseMode: .keep, minPlayTime: 30))
        settings.engineSettings.minPlayTime = 999
        #expect(settings.engineSettings.minPlayTime == 240)
        #expect(settings.notifyNowPlaying == false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEYCHAIN_TESTS"] == "1"))
    func keychainRoundTrip() throws {
        let keychain = KeychainSecretStore(service: "ShazamScrobbler.tests")
        let name = "test.\(UUID().uuidString)"
        try keychain.set("v1", for: name)
        try keychain.set("v2", for: name)
        #expect(try keychain.get(name) == "v2")
        try keychain.set(nil, for: name)
        #expect(try keychain.get(name) == nil)
    }
}
