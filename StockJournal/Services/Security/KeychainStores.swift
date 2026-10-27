import Foundation
import LocalAuthentication
import os
import Security

/// `SecretStore` on the login Keychain, service `AppPaths.keychainService`
struct KeychainSecretStore: SecretStore {
    func lookup(_ account: String) -> SecretLookup { KeychainHelper.lookupData(key: account) }

    @discardableResult
    func write(_ data: Data, account: String) -> Bool { KeychainHelper.saveData(key: account, value: data) }

    func delete(_ account: String) { KeychainHelper.delete(key: account) }
}

/// The App Lock recovery copy of the journal key, in the data protection Keychain with
/// access control `.userPresence`: macOS releases it only after Touch ID or the Mac login
/// password (Macs without Touch ID always ask for the password).
///
/// Creating such an item needs a build signed with a Team ID (the data protection Keychain
/// refuses ad-hoc signed apps with `errSecMissingEntitlement`). `store` then returns false
/// and the app offers "erase and start fresh" instead of recovery. The item is never
/// written to the file-based Keychain, which would silently ignore the access control.
struct KeychainPresenceStore: PresenceProtectedStore {
    static let account = "database_key_recovery"
    private static let logger = Logger(subsystem: "com.greenwick", category: "KeychainPresence")

    private var baseQuery: [String: Any] { Self.baseQuery(service: AppPaths.keychainService) }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func store(_ secret: Data) -> Bool {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            Self.logger.error("Could not create the access control for the recovery key")
            return false
        }
        delete()
        var query = baseQuery
        query[kSecValueData as String] = secret
        query[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            Self.logger.notice("Recovery key not stored (status \(status)); Forgot Password will offer erase only")
            return false
        }
        return true
    }

    func hasSecret() -> Bool {
        // Attributes only, and never show UI: an existing protected item answers
        // errSecInteractionNotAllowed or success without prompting
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    func retrieve(reason: String) async -> Data? {
        let service = AppPaths.keychainService
        return await withCheckedContinuation { continuation in
            // SecItemCopyMatching blocks while the system prompt is up: keep it off the main thread
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                context.localizedReason = reason
                var lookup = Self.baseQuery(service: service)
                lookup[kSecReturnData as String] = true
                lookup[kSecMatchLimit as String] = kSecMatchLimitOne
                lookup[kSecUseAuthenticationContext as String] = context
                var result: AnyObject?
                let status = SecItemCopyMatching(lookup as CFDictionary, &result)
                continuation.resume(returning: status == errSecSuccess ? result as? Data : nil)
            }
        }
    }

    func delete() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement {
            Self.logger.warning("Recovery key delete failed: \(status)")
        }
    }
}

/// `DeviceOwnerCheck` with LocalAuthentication: Touch ID, or the Mac login password
struct LocalAuthenticationOwnerCheck: DeviceOwnerCheck {
    private static let logger = Logger(subsystem: "com.greenwick", category: "DeviceOwner")

    func confirm(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // An account without a login password has no owner credential to ask for
            let noPassword = (error as? LAError)?.code == .passcodeNotSet
            Self.logger.notice("Owner check unavailable (no login password: \(noPassword))")
            return noPassword
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            Self.logger.notice("Owner check not confirmed")
            return false
        }
    }
}
