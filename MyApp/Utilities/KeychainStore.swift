import Foundation
import Security

/// Minimal Keychain wrapper — Security framework only, no dependency.
/// Stores small secrets: the stable device ID and the APNs token.
enum KeychainStore {
    private static let service = "app.pickhour.shared"

    /// Base query for every call. On macOS the legacy file keychain behaves
    /// differently (per-app ACL prompts); the data protection keychain gives
    /// the same semantics as iOS.
    private static func base(_ key: Key) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    enum Key: String {
        case deviceID = "device.id"
        case apnsToken = "apns.token"
        case apnsEnv = "apns.env"
    }

    static func string(for key: Key) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for key: Key) {
        delete(key)
        var query = base(key)
        query[kSecValueData as String] = Data(value.utf8)
        // Readable after first unlock so the app can register the device
        // on cold launch without user interaction.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ key: Key) {
        SecItemDelete(base(key) as CFDictionary)
    }
}


enum DeviceIdentity {
    static var deviceID: UUID {
        if let raw = KeychainStore.string(for: .deviceID), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        KeychainStore.set(id.uuidString, for: .deviceID)
        return id
    }
}
