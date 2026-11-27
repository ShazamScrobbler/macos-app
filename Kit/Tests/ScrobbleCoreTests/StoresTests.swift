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
        let stored = try #require(defaults.data(forKey: "accounts.v2"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("TOKEN"))
        #expect(String(decoding: stored, as: UTF8.self).contains("steph"))
        for (_, value) in defaults.dictionaryRepresentation() {
            if let text = value as? String { #expect(!text.contains("TOKEN")) }
            if let data = value as? Data { #expect(!String(decoding: data, as: UTF8.self).contains("TOKEN")) }
        }
    }

    final class FailingSecretStore: SecretStore, @unchecked Sendable {
        struct Boom: Error {}
        let inner = InMemorySecretStore()
        let failingName: String
        nonisolated(unsafe) var deleteAttempts: [String] = []
        init(failingName: String) { self.failingName = failingName }
        func get(_ name: String) throws -> String? { try inner.get(name) }
        func set(_ value: String?, for name: String) throws {
            if value == nil {
                deleteAttempts.append(name)
                if name == failingName { throw Boom() }
            }
            try inner.set(value, for: name)
        }
    }

    @Test func removeKeepsAccountAndAttemptsAllDeletesWhenOneThrows() throws {
        let failing = "\(account.id.rawValue).\(SecretField.sessionKey.rawValue)"
        let secrets = FailingSecretStore(failingName: failing)
        let store = AccountStore(defaults: freshDefaults(), secrets: secrets)
        store.upsert(account)
        try store.setSecret("S", .sessionKey, for: account.id)
        try store.setSecret("K", .apiKey, for: account.id)
        #expect(throws: FailingSecretStore.Boom.self) { try store.remove(account.id) }
        #expect(store.load() == [account])
        #expect(secrets.deleteAttempts.count == SecretField.allCases.count)
        #expect(store.secret(.apiKey, for: account.id) == nil)
    }

    @Test func corruptAccountsBlobIsBackedUpOnceAndNotOverwritten() throws {
        let defaults = freshDefaults()
        let garbage = Data("nope".utf8)
        defaults.set(garbage, forKey: "accounts.v2")
        let store = AccountStore(defaults: defaults, secrets: InMemorySecretStore())
        #expect(store.load() == [])
        #expect(defaults.data(forKey: "accounts.v2.unreadable") == garbage)
        store.upsert(account)
        #expect(store.load() == [account])
        #expect(defaults.data(forKey: "accounts.v2.unreadable") == garbage)
        // A second corruption never replaces the earlier backup.
        defaults.set(Data("other".utf8), forKey: "accounts.v2")
        #expect(store.load() == [])
        #expect(defaults.data(forKey: "accounts.v2.unreadable") == garbage)
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
