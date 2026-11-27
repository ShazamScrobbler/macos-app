import Foundation
import os

/// Non-secret account fields in UserDefaults (key "accounts.v2"); secrets in a SecretStore.
public final class AccountStore: @unchecked Sendable {
    static let defaultsKey = "accounts.v2"
    static let unreadableKey = "accounts.v2.unreadable"
    private static let log = Logger(subsystem: "ShazamScrobbler", category: "ui")
    private let defaults: UserDefaults
    private let secrets: any SecretStore

    public init(defaults: UserDefaults = .standard, secrets: any SecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
    }

    public func load() -> [Account] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        do { return try JSONDecoder().decode([Account].self, from: data) }
        catch {
            // Keep the unreadable blob (first one only) so a later save can't silently wipe the accounts.
            if defaults.data(forKey: Self.unreadableKey) == nil { defaults.set(data, forKey: Self.unreadableKey) }
            Self.log.error("Stored accounts are unreadable (\(data.count) bytes); kept a copy under \(Self.unreadableKey, privacy: .public)")
            return []
        }
    }

    public func upsert(_ account: Account) {
        var accounts = load()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account }
        else { accounts.append(account) }
        save(accounts)
    }

    public func remove(_ id: AccountID) throws {
        var firstError: Error?
        for field in SecretField.allCases {
            do { try secrets.set(nil, for: Self.name(field, id)) }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
        save(load().filter { $0.id != id })
    }

    public func secret(_ field: SecretField, for id: AccountID) -> String? {
        try? secrets.get(Self.name(field, id))
    }

    public func setSecret(_ value: String?, _ field: SecretField, for id: AccountID) throws {
        try secrets.set(value, for: Self.name(field, id))
    }

    private func save(_ accounts: [Account]) {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.defaultsKey)
    }

    static func name(_ field: SecretField, _ id: AccountID) -> String { "\(id.rawValue).\(field.rawValue)" }
}
