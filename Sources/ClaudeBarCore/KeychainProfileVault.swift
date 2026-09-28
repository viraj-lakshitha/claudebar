#if canImport(Security)
import Foundation
import Security

/// Stores each profile's secrets as a generic password owned by ClaudeBar.
public struct KeychainProfileVault: ProfileVault {
    public let service: String

    public init(service: String = "dev.claudebar.profile") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    public func load(_ id: UUID) throws -> ProfileSecret? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ClaudeBarError.keychain(Self.message(status))
        }
        return try JSONDecoder().decode(ProfileSecret.self, from: data)
    }

    public func save(_ secret: ProfileSecret, for id: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query(id) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(id)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "ClaudeBar saved account"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClaudeBarError.keychain(Self.message(status)) }
    }

    public func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClaudeBarError.keychain(Self.message(status))
        }
    }

    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }
}
#endif
