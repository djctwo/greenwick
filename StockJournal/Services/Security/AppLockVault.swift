import CryptoKit
import Foundation
import os

// MARK: - Storage seams

/// What reading one item found. Only `.absent` (the Keychain's errSecItemNotFound) means the
/// item doesn't exist; any other error is `.failed` and must never be taken for "absent".
enum SecretLookup: Equatable, Sendable {
    case found(Data)
    case absent
    case failed(Int32)
}

/// Where the vault keeps its items (the Keychain in the app, a dictionary in tests)
protocol SecretStore: Sendable {
    func lookup(_ account: String) -> SecretLookup
    @discardableResult func write(_ data: Data, account: String) -> Bool
    func delete(_ account: String)
}

extension SecretStore {
    /// The item's data; nil when it is absent OR couldn't be read. Decisions that must not
    /// treat a read error as "absent" (is the lock on? may a key be created?) use `lookup`.
    func read(_ account: String) -> Data? {
        if case .found(let data) = lookup(account) { return data }
        return nil
    }
}

/// A secret that can only be read after the Mac's owner confirms with Touch ID or the Mac
/// login password (Keychain access control `.userPresence`).
protocol PresenceProtectedStore: Sendable {
    /// Store `secret`. Returns false when this build can't create protected items.
    func store(_ secret: Data) -> Bool
    /// Whether a secret is stored (checked without prompting)
    func hasSecret() -> Bool
    /// Read the secret; the system asks for Touch ID or the Mac password first.
    func retrieve(reason: String) async -> Data?
    func delete()
}

/// Asks the Mac's owner to confirm with Touch ID or the Mac login password before
/// something irreversible. Needs no Keychain entitlement, so it works in ad-hoc builds too.
protocol DeviceOwnerCheck: Sendable {
    /// True once the owner confirmed; false if they cancelled or failed
    func confirm(reason: String) async -> Bool
}

// MARK: - Vault

/// Holds the journal's encryption key and, with App Lock on, keeps it wrapped so that
/// nothing can decrypt the journal before the lock password is entered.
///
/// - App Lock off: the 256-bit key is a plain Keychain item (`database_encryption_key`).
/// - App Lock on: the key is sealed (AES-256-GCM) with a key derived from the lock password
///   (PBKDF2-SHA256, `defaultIterations`, random per-install salt) and stored as
///   `database_key_wrapped`. The plain item is deleted. A second copy goes into a
///   `.userPresence` Keychain item so "Forgot password?" can recover with Touch ID or the
///   Mac password, when the build is allowed to create such items.
/// - Turning the lock on, changing the password and migrating an older install all
///   rotate to a NEW key (old copies of the key may survive in Keychain or disk backups),
///   in three crash-safe steps: `beginRotation`, `DatabaseManager.rekey`, `commitRotation`.
/// - Older versions stored only a password hash (`app_lock_hash`) next to the plain key.
///   The first successful unlock rotates to a new wrapped key and removes both.
struct AppLockVault: Sendable {
    let store: any SecretStore
    let presence: any PresenceProtectedStore
    /// Confirms the Mac's owner before "erase all local data"
    var owner: any DeviceOwnerCheck = LocalAuthenticationOwnerCheck()
    /// The last journal generation saved on this Mac (rollback detection), kept next to the keys
    var ledger: JournalLedger = .live
    var iterations: UInt32 = AppLockVault.defaultIterations
    /// Failed password checks and the lockout (lock screen and Settings share it)
    var throttle: UnlockThrottle = .live

    /// PBKDF2-SHA256 rounds for the lock password (OWASP 2023 guidance: 600,000)
    static let defaultIterations: UInt32 = 600_000
    static let minimumPasswordLength = 8

    enum Account {
        static let plainKey = "database_encryption_key"
        static let wrappedKey = "database_key_wrapped"
        static let legacyHash = "app_lock_hash"
        static let previousKey = "database_key_previous"
        /// SHA-256 of the key the Touch ID / Mac password recovery copy holds (read without
        /// a prompt, so an outdated copy can be replaced at unlock)
        static let recoveryFingerprint = "database_key_recovery_fingerprint"
    }

    private static let logger = Logger(subsystem: "com.greenwick", category: "AppLockVault")

    /// The vault used by the app (Keychain service from `AppPaths`)
    static var live: AppLockVault {
        AppLockVault(store: KeychainSecretStore(), presence: KeychainPresenceStore())
    }

    // MARK: State

    /// The lock is off only when the Keychain says both lock items don't exist: an item that
    /// can't be read counts as present (fail closed: the lock screen shows)
    var isLockEnabled: Bool { hasWrappedKey || store.lookup(Account.legacyHash) != .absent }
    /// A wrapped key exists, or its item can't be read (fail closed)
    var hasWrappedKey: Bool { store.lookup(Account.wrappedKey) != .absent }
    /// A lock item exists but the Keychain wouldn't return it right now
    var hasUnreadableLockItem: Bool { isUnreadable(Account.wrappedKey) || isUnreadable(Account.legacyHash) }
    /// A lock item or the plain key exists but can't be read right now (Erase is refused then)
    var hasUnreadableKeyItem: Bool { hasUnreadableLockItem || isUnreadable(Account.plainKey) }
    var isRecoveryAvailable: Bool { presence.hasSecret() }

    private func isUnreadable(_ account: String) -> Bool {
        if case .failed = store.lookup(account) { return true }
        return false
    }

    // MARK: Lock off

    /// The plain key (App Lock off). Creates one only when `createIfMissing` is set, which
    /// the caller does only when no encrypted journal exists yet; an unreadable key is
    /// never replaced over existing data.
    func plainKey(createIfMissing: Bool) throws -> SymmetricKey {
        switch store.lookup(Account.plainKey) {
        case .found(let stored):
            if let raw = Data(base64Encoded: stored), raw.count == 32 { return SymmetricKey(data: raw) }
        case .failed(let status):
            // Never write a new key over one that exists but couldn't be read
            Self.logger.error("Journal key unreadable (status \(status))")
            throw VaultError.keyUnavailable
        case .absent:
            break
        }
        guard createIfMissing, !hasWrappedKey else { throw VaultError.keyUnavailable }
        let key = SymmetricKey(size: .bits256)
        guard store.write(Self.encodePlain(key), account: Account.plainKey) else {
            throw VaultError.storeFailed
        }
        Self.logger.info("Generated a new journal key")
        return key
    }

    // MARK: Unlock

    /// The keys that may open the journal after a correct password, best first.
    struct UnlockKeys: Sendable {
        /// The current wrapped key (nil for an install from before key wrapping)
        let primary: Data?
        /// Keys left by an interrupted rotation (previous wrapped key, old plain key):
        /// tried when the primary doesn't open the file, which is then re-sealed
        let fallbacks: [Data]
        /// An install from before key wrapping: rotate to a new wrapped key after opening
        let needsRotation: Bool
    }

    /// Check `password` and return the keys that may decrypt the journal. Nothing is
    /// deleted here: leftovers are removed by `finishUnlock()` once the journal is open.
    /// `notLocked` only when the Keychain says neither lock item exists; an item that can't
    /// be read throws `keychainUnreadable` (fail closed: never opened without the password).
    func unlockKeys(password: String, mayCreateKey: Bool) throws -> UnlockKeys {
        switch store.lookup(Account.wrappedKey) {
        case .found(let blob):
            let primary = try unwrap(blob, password: password)
            var fallbacks: [Data] = []
            if let previous = store.read(Account.previousKey),
               let key = try? unwrap(previous, password: password) {
                fallbacks.append(Self.raw(key))
            }
            if let plain = try? plainKey(createIfMissing: false) { fallbacks.append(Self.raw(plain)) }
            return UnlockKeys(primary: Self.raw(primary), fallbacks: fallbacks, needsRotation: false)
        case .failed(let status):
            Self.logger.error("App Lock key unreadable (status \(status)); staying locked")
            throw VaultError.keychainUnreadable
        case .absent:
            break
        }
        let legacy: Data
        switch store.lookup(Account.legacyHash) {
        case .found(let data):
            legacy = data
        case .failed(let status):
            Self.logger.error("App Lock password hash unreadable (status \(status)); staying locked")
            throw VaultError.keychainUnreadable
        case .absent:
            throw VaultError.notLocked
        }
        guard let legacyHash = String(data: legacy, encoding: .utf8) else { throw VaultError.keyUnavailable }
        guard PasswordHasher.verify(password, against: legacyHash) else { throw VaultError.wrongPassword }
        let key = try plainKey(createIfMissing: mayCreateKey)
        return UnlockKeys(primary: nil, fallbacks: [Self.raw(key)], needsRotation: true)
    }

    /// Check the password only
    func verify(password: String) throws {
        _ = try unlockKeys(password: password, mayCreateKey: false)
    }

    /// The journal is open with the primary key: remove what an interrupted rotation or an
    /// older version left behind, and make sure the recovery copy holds this key. A password
    /// change interrupted before step 3 leaves the copy on the old key, which no longer opens
    /// the journal: its fingerprint tells, and it is replaced.
    func finishUnlock(primary: SymmetricKey) {
        store.delete(Account.previousKey)
        store.delete(Account.plainKey)
        store.delete(Account.legacyHash)
        guard !presence.hasSecret() || store.read(Account.recoveryFingerprint) != Self.fingerprint(primary) else {
            return
        }
        _ = storeRecoveryCopy(primary)
    }

    /// Replace the recovery copy with `key`; its fingerprint follows. Returns whether this
    /// build could store it.
    private func storeRecoveryCopy(_ key: SymmetricKey) -> Bool {
        presence.delete()
        guard presence.store(Self.raw(key)) else {
            store.delete(Account.recoveryFingerprint)
            return false
        }
        store.write(Self.fingerprint(key), account: Account.recoveryFingerprint)
        return true
    }

    /// Identifies a key without revealing it (SHA-256 of a random 256-bit key)
    static func fingerprint(_ key: SymmetricKey) -> Data {
        Data(SHA256.hash(data: Data("greenwick-recovery-key".utf8) + raw(key)))
    }

    // MARK: Key rotation (turn on / change password / migrate)

    /// Step 1 of 3: store `newKey` wrapped with `password` while the old key stays usable
    /// (the old plain key is left in place; an old wrapped key is kept as `previousKey`,
    /// wrapped with the new password). Step 2 is `DatabaseManager.rekey(to:)`, step 3
    /// `commitRotation(to:)`. An interruption after any step leaves the journal
    /// decryptable: `unlockKeys` offers the old key as a fallback.
    func beginRotation(to newKey: SymmetricKey, password: String, current: SymmetricKey) throws {
        try Self.checkStrength(password)
        if hasWrappedKey {
            guard store.write(try wrap(current, password: password), account: Account.previousKey) else {
                throw VaultError.storeFailed
            }
        } else if (try? plainKey(createIfMissing: false)).map(Self.raw) != Self.raw(current) {
            // Keep the current key reachable until the file is re-sealed
            guard store.write(Self.encodePlain(current), account: Account.plainKey) else {
                throw VaultError.storeFailed
            }
        }
        guard store.write(try wrap(newKey, password: password), account: Account.wrappedKey) else {
            store.delete(Account.previousKey)
            throw VaultError.storeFailed
        }
    }

    /// Step 3 of 3 (the journal file is sealed with `newKey`): point the recovery copy at
    /// the new key and delete every old key. Returns whether recovery is available.
    func commitRotation(to newKey: SymmetricKey) -> Bool {
        let hasRecovery = storeRecoveryCopy(newKey)
        store.delete(Account.previousKey)
        store.delete(Account.plainKey)
        store.delete(Account.legacyHash)
        return hasRecovery
    }

    /// Turn App Lock off: the key goes back to a plain Keychain item. Returns the key.
    func disableLock(password: String, key: SymmetricKey) throws {
        try verify(password: password)
        try restorePlainKey(key)
    }

    /// "Forgot password?": read the recovery copy (the system asks for Touch ID or the Mac
    /// password). Changes nothing: call `removeLock(keeping:)` once the key has opened
    /// the journal. Throws `recoveryUnavailable` when there is no recovery copy.
    func recoveryKey(reason: String) async throws -> SymmetricKey {
        guard presence.hasSecret() else { throw VaultError.recoveryUnavailable }
        guard let raw = await presence.retrieve(reason: reason), raw.count == 32 else {
            throw VaultError.ownerNotConfirmed
        }
        return SymmetricKey(data: raw)
    }

    /// Turn the lock off, keeping `key` (which opened the journal) as the plain key
    func removeLock(keeping key: SymmetricKey) throws {
        try restorePlainKey(key)
    }

    /// Delete every item (used by "erase all local data")
    func removeEverything() {
        ledger.remove()
        store.delete(Account.plainKey)
        store.delete(Account.wrappedKey)
        store.delete(Account.legacyHash)
        store.delete(Account.previousKey)
        store.delete(Account.recoveryFingerprint)
        presence.delete()
        throttle.reset()
    }

    // MARK: Wrapping

    struct WrappedKey: Codable {
        var version = 1
        let salt: Data
        let iterations: UInt32
        let sealed: Data
    }

    func wrap(_ key: SymmetricKey, password: String) throws -> Data {
        let salt = KeyDerivation.generateSalt()
        let kek = try Self.passwordKey(password, salt: salt, iterations: iterations)
        let sealed = try DatabaseEncryption.seal(Self.raw(key), key: kek)
        return try JSONEncoder().encode(WrappedKey(salt: salt, iterations: iterations, sealed: sealed))
    }

    func unwrap(_ blob: Data, password: String) throws -> SymmetricKey {
        guard let wrapped = try? JSONDecoder().decode(WrappedKey.self, from: blob),
              wrapped.version == 1, wrapped.iterations >= 1 else {
            throw VaultError.keyUnavailable
        }
        let kek = try Self.passwordKey(password, salt: wrapped.salt, iterations: wrapped.iterations)
        guard let raw = try? DatabaseEncryption.open(wrapped.sealed, key: kek), raw.count == 32 else {
            throw VaultError.wrongPassword
        }
        return SymmetricKey(data: raw)
    }

    private func restorePlainKey(_ key: SymmetricKey) throws {
        guard store.write(Self.encodePlain(key), account: Account.plainKey) else { throw VaultError.storeFailed }
        store.delete(Account.wrappedKey)
        store.delete(Account.previousKey)
        store.delete(Account.legacyHash)
        store.delete(Account.recoveryFingerprint)
        presence.delete()
    }

    private static func passwordKey(_ password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard let derived = KeyDerivation.deriveKey(password: password, salt: salt, iterations: iterations) else {
            throw VaultError.wrongPassword
        }
        return SymmetricKey(data: derived)
    }

    static func checkStrength(_ password: String) throws {
        guard password.count >= minimumPasswordLength else { throw VaultError.passwordTooShort }
    }

    static func raw(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// Plain-key format kept from earlier versions: base64 text
    private static func encodePlain(_ key: SymmetricKey) -> Data {
        Data(raw(key).base64EncodedString().utf8)
    }
}
