import CryptoKit
import Foundation

/// Turning App Lock on and off, and changing its password (each moves the journal to a new key).
///
/// Each runs as a key operation (`performKeyOperation`): no unlock, recovery or erase can run
/// meanwhile, and a lock asked for meanwhile waits until it ends. Quitting can still close the
/// journal during an `await`, so after each one the code checks that the journal it started
/// with is still open before touching it, and it never deletes a key unless the file on disk
/// was re-sealed and read back with the new one.
extension AppState {
    /// How a key change ended
    enum KeyChange: Equatable {
        /// All three steps done. `hasRecovery`: Touch ID / Mac password recovery is available.
        case done(hasRecovery: Bool)
        /// The new password is in force, but the journal or a screenshot couldn't be re-sealed
        /// yet (the journal was closed by a lock, or a write failed): the next unlock finishes
        /// the job with the old key, which stays stored (wrapped by the new password) until then
        case finishesAtNextUnlock
    }

    // MARK: - Key rotation

    /// Rotate the open journal and its screenshots to a brand-new key wrapped with
    /// `password`, in three steps that each leave everything decryptable if the app stops in
    /// between. Runs inside a key operation (enable, change password, or the migration at
    /// unlock). The old key is deleted only once the journal file AND every screenshot read
    /// back with the new key.
    ///
    /// Throws only when nothing changed (step 1 failed). Once step 1 is stored the new
    /// password is the one that unlocks, so a later problem is reported as
    /// `.finishesAtNextUnlock`, never as a failure the user would read as "old password
    /// still valid".
    @MainActor
    func rotateKey(password: String) async throws -> KeyChange {
        let manager = database
        guard manager.isOpen, let current = manager.encryptionKey else {
            throw AppLockVault.VaultError.keyUnavailable
        }
        // An earlier change left screenshots on an older key: finish that first (or change
        // nothing), since step 1 replaces the older key that is still stored
        try await finishPendingScreenshots(to: current)
        guard database === manager, manager.isOpen else { throw AppLockVault.VaultError.lockedMeanwhile }
        let newKey = SymmetricKey(size: .bits256)
        let vault = self.vault
        let currentRaw = AppLockVault.raw(current)
        let newRaw = AppLockVault.raw(newKey)
        // 1. Store the new key wrapped by the password; the old key stays reachable
        let step1 = Task.detached(priority: .userInitiated) {
            try vault.beginRotation(to: SymmetricKey(data: newRaw), password: password,
                                    current: SymmetricKey(data: currentRaw))
        }
        await hooks.whileRotationBegins?()
        try await step1.value
        isAppLockEnabled = true
        await hooks.afterRotationBegan?()
        // Quitting may have closed the journal during the await: its final save used the old
        // key, so the old key must stay. The next unlock re-seals and finishes.
        guard database === manager, manager.isOpen else {
            Self.logger.notice("Key change: the journal closed meanwhile; it finishes at the next unlock")
            return .finishesAtNextUnlock
        }
        // 2. Re-seal the journal file with the new key (one atomic, flushed write), then read
        //    it back: only a file that opens with the new key lets the old key go
        do {
            try manager.rekey(to: newKey)
            guard manager.fileOpens(with: newKey) else { throw DatabaseManager.StorageError.serializationFailed }
        } catch {
            Self.logger.error("Key change: re-sealing failed (\(error.localizedDescription)); finishes at next unlock")
            return .finishesAtNextUnlock
        }
        //    Then every screenshot (each one read back): one that still needs the old key keeps it
        let pending = await resealScreenshots(from: [current], to: newKey)
        guard pending.isEmpty else {
            pendingScreenshotKeys = [AppLockVault.raw(current)]
            Self.logger.error("Key change: \(pending.count) screenshot(s) not re-sealed; finishes at next unlock")
            return .finishesAtNextUnlock
        }
        // 3. Recovery copy to the new key; delete every old key
        return .done(hasRecovery: vault.commitRotation(to: newKey))
    }

    // MARK: - Turning the lock on and off

    /// Turn App Lock on: the journal moves to a new key that only the password unwraps.
    @MainActor
    func enableAppLock(password: String) async throws -> KeyChange {
        try AppLockVault.checkStrength(password)
        let change = try await performKeyOperation { try await rotateKey(password: password) }
        Self.logger.notice("App Lock turned on")
        return change
    }

    /// Change the lock password (the current one must be right, under the shared
    /// wrong-password limit); rotates the key too
    @MainActor
    @discardableResult
    func changeAppLockPassword(current: String, new: String) async throws -> KeyChange {
        try AppLockVault.checkStrength(new)
        let change = try await performKeyOperation {
            do {
                try await checkLockPassword(current)
            } catch {
                Self.logger.notice("App Lock: password change refused (current password not confirmed)")
                throw error
            }
            return try await rotateKey(password: new)
        }
        Self.logger.notice("App Lock password changed")
        return change
    }

    /// Turn App Lock off (the password must be right). A lock asked for meanwhile waits until
    /// this ends. If the journal closed meanwhile (quitting), nothing changes: the password
    /// still unlocks it.
    @MainActor
    func disableAppLock(password: String) async throws {
        try await performKeyOperation { try await disableNow(password: password) }
    }

    @MainActor
    private func disableNow(password: String) async throws {
        let manager = database
        guard manager.isOpen, let key = manager.encryptionKey else {
            throw AppLockVault.VaultError.keyUnavailable
        }
        do {
            try await checkLockPassword(password)
        } catch {
            Self.logger.notice("App Lock: turning off refused (password not confirmed)")
            throw error
        }
        await hooks.afterDisablePasswordCheck?()
        // Turning off keeps only the journal's key: screenshots must not need an older one
        try await finishPendingScreenshots(to: key)
        guard !isLocked, database === manager, manager.isOpen else {
            Self.logger.notice("App Lock: turning off skipped, the journal closed meanwhile")
            throw AppLockVault.VaultError.lockedMeanwhile
        }
        try vault.removeLock(keeping: key)
        isAppLockEnabled = false
        Self.logger.notice("App Lock turned off")
    }

    /// Check the lock password off the main thread. Counts toward the same wrong-password
    /// limit as the lock screen (`UnlockThrottle`), and refuses while its wait runs.
    @MainActor
    func checkLockPassword(_ password: String) async throws {
        let throttle = vault.throttle
        try throttle.checkAllowed()
        let vault = self.vault
        do {
            try await Task.detached(priority: .userInitiated) { try vault.verify(password: password) }.value
        } catch AppLockVault.VaultError.wrongPassword {
            let (attempts, lockout) = try throttle.recordFailure()
            if lockout > 0 { throw AppLockVault.VaultError.tooManyAttempts(seconds: lockout) }
            Self.logger.notice("App Lock: wrong password in Settings (\(attempts))")
            throw AppLockVault.VaultError.wrongPassword
        }
        throttle.reset()
    }
}
