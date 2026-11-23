import Foundation
import Security

public protocol SecretStore: Sendable {
    func get(_ name: String) throws -> String?
    func set(_ value: String?, for name: String) throws
}

public enum SecretField: String, Sendable, CaseIterable {
    case sessionKey, token, apiKey, apiSecret
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Generic-password items in the login keychain. Access is tied to the app's designated
/// requirement, so the stable signing certificate keeps it prompt-free across updates (§11).
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "ShazamScrobbler") { self.service = service }

    public func get(_ name: String) throws -> String? {
        var query = baseQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func set(_ value: String?, for name: String) throws {
        let query = baseQuery(name)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "ShazamScrobbler"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    public init() {}

    public func get(_ name: String) throws -> String? { lock.withLock { values[name] } }
    public func set(_ value: String?, for name: String) throws { lock.withLock { values[name] = value } }
}
