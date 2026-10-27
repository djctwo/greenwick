import CryptoKit
import Foundation

/// "Forgot password?" on the lock screen: recovery with Touch ID / the Mac password (signed
/// builds), or erasing all local data. Both are key operations (`performKeyOperation`), so
/// neither can run while an unlock or another App Lock change is still in progress.
extension AppState {
    /// "Forgot password?" with Touch ID / Mac password: removes the lock, keeps the journal.
    /// The lock is only removed once the recovered key has actually opened (decrypted) the
    /// journal. A journal older than the last one this Mac saved then still waits for the
    /// owner's explicit confirmation (`olderJournal`). A recovery copy that no longer opens
    /// the journal (an interrupted password change) throws `recoveryKeyOutdated`, and the
    /// lock screen then offers erasing instead.
    @MainActor
    func recoverWithDeviceOwner() async throws {
        try await performKeyOperation { try await recoverNow() }
    }

    @MainActor
    private func recoverNow() async throws {
        let key = try await vault.recoveryKey(reason: "remove the Greenwick app lock")
        guard isLocked else { return }
        let manager: DatabaseManager?
        if let held = heldJournal {
            // The last lock couldn't save: the journal in memory is the newest one. Its key
            // also sealed the file on disk, so it must be the recovered key.
            guard let heldKey = held.encryptionKey, AppLockVault.raw(heldKey) == AppLockVault.raw(key) else {
                throw AppLockVault.VaultError.recoveryKeyOutdated
            }
            manager = held
        } else {
            do {
                manager = try openManager(key: key)
            } catch let older as DatabaseManager.OlderJournal {
                // The key decrypted the file (the check comes after decryption); it is only older
                manager = nil
                holdOlderJournal(older)
            } catch let error where !DatabaseManager.isUnreadable(error) {
                throw error // the disk, not the key: nothing changed, try again later
            } catch {
                throw AppLockVault.VaultError.recoveryKeyOutdated
            }
        }
        try vault.removeLock(keeping: key)
        if let manager {
            if manager === heldJournal { reinstallHeldJournal(manager) } else { install(manager) }
        }
        isAppLockEnabled = false
        keychainUnreadableAtLaunch = false
        isLocked = false
        Self.logger.notice("App Lock removed with Touch ID / Mac password recovery")
    }

    /// "Forgot password?" without recovery: once the Mac's owner confirms (Touch ID or the
    /// login password), delete the journal, its set-aside copies, screenshots and every key,
    /// then start an empty journal. Without that confirmation anyone at the lock screen could
    /// destroy the journal for good. If the journal file itself can't be deleted, nothing
    /// else is deleted either (`journalNotDeleted`): removing the keys would leave a file no
    /// key opens and an app that fails at every launch.
    @MainActor
    func eraseAllLocalData() async throws {
        try await performKeyOperation { try await eraseNow() }
    }

    @MainActor
    private func eraseNow() async throws {
        // A key item that can't be read right now (e.g. a locked login keychain, even with
        // App Lock off): erasing couldn't start a new journal either, so delete nothing
        guard !vault.hasUnreadableKeyItem else {
            Self.logger.notice("Erase all local data refused: the Keychain can't be read")
            throw AppLockVault.VaultError.keychainUnreadable
        }
        guard await vault.owner.confirm(reason: "erase all Greenwick data on this Mac") else {
            Self.logger.notice("Erase all local data: owner not confirmed, nothing erased")
            throw AppLockVault.VaultError.eraseNotConfirmed
        }
        guard isLocked else { return }
        let files = FileManager.default
        let removal = Result { try files.removeItem(atPath: databasePath) }
        // Checked by path without following a symlink: the journal must really be gone
        guard (try? files.attributesOfItem(atPath: databasePath)) == nil else {
            if case .failure(let error) = removal {
                Self.logger.error("Erase: the journal file couldn't be deleted: \(error.localizedDescription)")
            }
            throw AppLockVault.VaultError.journalNotDeleted
        }
        heldJournal?.close(saving: false)
        heldJournal = nil
        let directory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
        let name = URL(fileURLWithPath: databasePath).lastPathComponent
        for file in DatabaseEncryption.journalFiles(in: directory, databaseName: name) {
            try? files.removeItem(at: file)
        }
        try? files.removeItem(at: screenshotsDirectory)
        vault.removeEverything() // also resets the wrong-password count
        olderJournal = nil
        keychainUnreadableAtLaunch = false
        isAppLockEnabled = false
        isDatabaseFailed = false
        openJournalWithPlainKey()
        isLocked = false
        Self.logger.notice("All local data erased")
    }
}
