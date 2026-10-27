import Foundation
import os

/// Counts wrong App Lock passwords and imposes a growing wait (exponential backoff).
///
/// Kept in the Keychain (same service as the keys), so a restart doesn't reset it. Every place
/// that checks the lock password shares it: the lock screen, "Open Anyway" for an older
/// journal, and Change Password / Turn Off in Settings. Otherwise a script driving the
/// unlocked app could guess the password through Settings without any wait. Fails closed:
/// while either item exists but can't be read, no password may be checked
/// (`keychainUnreadable`) and the stored count is never overwritten.
struct UnlockThrottle: Sendable {
    let store: any SecretStore
    /// The clock (tests move it forward)
    var now: @Sendable () -> Date = { Date() }

    /// Keychain accounts (unchanged from earlier versions, so existing counts carry over)
    static let attemptsAccount = "lock_failed_attempts"
    static let lockoutUntilAccount = "lock_lockout_until"
    /// Wrong passwords allowed before the first wait
    static let freeAttempts = 5

    private static let logger = Logger(subsystem: "com.greenwick", category: "UnlockThrottle")

    static var live: UnlockThrottle { UnlockThrottle(store: KeychainSecretStore()) }

    /// Wrong passwords since the last right one (0 when the count can't be read; `refusal`
    /// and `recordFailure` treat that case as locked out)
    var failedAttempts: Int { (try? storedAttempts()) ?? 0 }

    /// Seconds left before the next password may be checked (nil: no wait, or the item
    /// can't be read: see `refusal`)
    var remainingLockout: Int? {
        guard case .found(let raw) = store.lookup(Self.lockoutUntilAccount),
              let until = TimeInterval(String(decoding: raw, as: UTF8.self)) else { return nil }
        let remaining = until - now().timeIntervalSince1970
        guard remaining > 0 else { return nil }
        return max(1, Int(saturating: min(remaining.rounded(.up), 86_400)))
    }

    /// Why no password may be checked right now (nil: one may): a wait is running, or an
    /// item exists but the Keychain wouldn't return it (fail closed)
    var refusal: AppLockVault.VaultError? {
        do { try checkReadable() } catch { return .keychainUnreadable }
        return remainingLockout.map { .tooManyAttempts(seconds: $0) }
    }

    /// Throws `tooManyAttempts` while a wait is running, `keychainUnreadable` while the
    /// count or the wait can't be read
    func checkAllowed() throws {
        if let refusal { throw refusal }
    }

    /// A wrong password: count it and start the wait it earns. Returns the new count and
    /// the wait in seconds (0: none yet). Throws `keychainUnreadable`, writing nothing, when
    /// the stored count or wait can't be read (the count is never restarted at 1).
    @discardableResult
    func recordFailure() throws -> (attempts: Int, lockout: Int) {
        try checkReadable()
        let attempts = try storedAttempts() + 1
        store.write(Data(String(attempts).utf8), account: Self.attemptsAccount)
        let lockout = Self.lockoutDuration(for: attempts)
        if lockout > 0 {
            Self.logger.notice("App Lock: \(attempts) failed attempts, locked out for \(lockout) s")
            let until = now().timeIntervalSince1970 + TimeInterval(lockout)
            store.write(Data(String(until).utf8), account: Self.lockoutUntilAccount)
        }
        return (attempts, lockout)
    }

    /// Throws `keychainUnreadable` when the count or the wait exists but can't be read
    private func checkReadable() throws {
        for account in [Self.attemptsAccount, Self.lockoutUntilAccount] {
            if case .failed(let status) = store.lookup(account) {
                Self.logger.error("Wrong-password limit unreadable (status \(status)); nothing checked or written")
                throw AppLockVault.VaultError.keychainUnreadable
            }
        }
    }

    /// The stored count; throws `keychainUnreadable` when it exists but can't be read
    private func storedAttempts() throws -> Int {
        switch store.lookup(Self.attemptsAccount) {
        case .found(let raw): return Int(String(decoding: raw, as: UTF8.self)) ?? 0
        case .absent: return 0
        case .failed(let status):
            Self.logger.error("Wrong-password count unreadable (status \(status)); not overwritten")
            throw AppLockVault.VaultError.keychainUnreadable
        }
    }

    /// The right password: start counting from zero
    func reset() {
        store.delete(Self.attemptsAccount)
        store.delete(Self.lockoutUntilAccount)
    }

    /// Wait after `attempts` wrong passwords, in seconds
    static func lockoutDuration(for attempts: Int) -> Int {
        switch attempts {
        case ..<freeAttempts: 0
        case 5: 30
        case 6: 60
        case 7: 300
        case 8: 900
        default: 1800
        }
    }

    /// "Too many attempts. Try again in …"
    static func waitMessage(seconds: Int) -> String {
        seconds > 60
            ? "Too many attempts. Try again in \(seconds / 60) minutes."
            : "Too many attempts. Try again in \(seconds) seconds."
    }
}
