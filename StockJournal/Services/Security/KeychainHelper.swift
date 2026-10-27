import Foundation
import Security
import os

/// Secure storage for API keys and sensitive data using macOS Keychain
enum KeychainHelper {
    private static let logger = Logger(subsystem: "com.greenwick", category: "Keychain")
    /// Per-bundle service name, so test builds never touch the release build's items.
    private static var service: String { AppPaths.keychainService }

    /// Save a string value to the Keychain (replacing any existing item). Returns true on success.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        saveData(key: key, value: Data(value.utf8))
    }

    /// Save raw bytes to the Keychain (replacing any existing item). Returns true on success.
    ///
    /// An existing item is updated in place, never deleted first: if the write fails, the
    /// previous value (for example the only wrapped copy of the journal key during a key
    /// rotation) is still there.
    @discardableResult
    static func saveData(key: String, value: Data) -> Bool {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        var status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var add = item
            add[kSecValueData as String] = value
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain save failed for \(key): \(status)")
            return false
        }
        return true
    }

    /// Read raw bytes from the Keychain. Only errSecItemNotFound is `.absent`; any other
    /// error (locked keychain, access denied, a cancelled prompt) is `.failed`.
    static func lookupData(key: String) -> SecretLookup {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failed(errSecDecode) }
            return .found(data)
        case errSecItemNotFound:
            return .absent
        default:
            logger.error("Keychain read failed for \(key): \(status)")
            return .failed(status)
        }
    }

    /// Read a string value from the Keychain
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain delete failed for \(key): \(status)")
        }
    }

    // MARK: - Convenience Keys

    static var anthropicAPIKey: String? {
        get { read(key: "anthropic_api_key") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "anthropic_api_key", value: newValue)
            } else {
                delete(key: "anthropic_api_key")
            }
        }
    }

    static var finnhubAPIKey: String? {
        get { read(key: "finnhub_api_key") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "finnhub_api_key", value: newValue)
            } else {
                delete(key: "finnhub_api_key")
            }
        }
    }

    /// Migrate API keys from UserDefaults to Keychain (one-time)
    static func migrateFromUserDefaults() {
        if let key = UserDefaults.standard.string(forKey: "anthropic_api_key"), !key.isEmpty {
            if read(key: "anthropic_api_key") == nil {
                save(key: "anthropic_api_key", value: key)
                UserDefaults.standard.removeObject(forKey: "anthropic_api_key")
                logger.info("Migrated Anthropic API key from UserDefaults to Keychain")
            }
        }
        if let key = UserDefaults.standard.string(forKey: "finnhubAPIKey"), !key.isEmpty {
            if read(key: "finnhub_api_key") == nil {
                save(key: "finnhub_api_key", value: key)
                UserDefaults.standard.removeObject(forKey: "finnhubAPIKey")
                logger.info("Migrated Finnhub API key from UserDefaults to Keychain")
            }
        }
    }
}
