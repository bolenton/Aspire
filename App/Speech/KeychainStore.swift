import Foundation
import Security

/// Where secrets live. API keys are the only data Lantern ever holds that
/// could cost a parent money if leaked, so they belong in the Keychain —
/// not in `@AppStorage`, which is plist-readable from a device backup.
/// Non-secret preferences (endpoints, model names, provider choice) stay in
/// UserDefaults; this store is exclusively for keys.
enum KeychainStore {
    /// One bundle-wide service bucket; the account string is the key name.
    static let service = "com.bolenton.lantern"

    /// Known key accounts, so callers never stringly-type the same secret two
    /// different ways and end up unable to read what they wrote.
    enum Key {
        static let brain = "brain.apiKey"
        static let elevenLabs = "tts.elevenlabs.key"
        static let openAI = "tts.openai.key"
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Stores a non-empty value; an empty/nil value deletes the item, so the
    /// settings UI clearing a field genuinely removes the secret.
    static func set(_ value: String?, for account: String) {
        guard let value, !value.isEmpty else {
            delete(account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Readable only on this device after first unlock — never synced
            // to iCloud or restored to a different device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// One-time read-through migration for a secret that used to live in
    /// UserDefaults: prefer the Keychain, fall back to a plaintext default,
    /// and when the default is found promote it into the Keychain and wipe
    /// the plaintext copy. After the first launch on an updated build the
    /// secret exists only in the Keychain.
    static func migratedValue(account: String, userDefaultsKey: String) -> String? {
        if let secure = get(account) { return secure }
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: userDefaultsKey), !legacy.isEmpty else {
            return nil
        }
        set(legacy, for: account)
        defaults.removeObject(forKey: userDefaultsKey)
        return legacy
    }
}
