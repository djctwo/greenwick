import AppKit
import CryptoKit
import Foundation

/// App Lock: the key-operation gate, unlocking and locking ("Forgot password?":
/// `AppState+Recovery.swift`; turning the lock on/off and changing its password:
/// `AppState+KeyChange.swift`). Also the owner's confirmation for opening a journal older
/// than the last one this Mac saved (`olderJournal`, rollback protection).
extension AppState {
    enum UnlockResult: Equatable {
        case unlocked
        case wrongPassword
        /// The password was right, but the journal on disk is older than the last one this
        /// Mac saved: `olderJournal` is set and nothing was opened
        case olderJournal
        case failed(String)
    }

    // MARK: - One key operation at a time

    /// Run an App Lock key operation (unlock, Forgot Password, erase, turning the lock on or
    /// off, changing its password). Only one runs at a time: another one throws `busy`, and
    /// the lock screen disables its buttons meanwhile (`isKeyOperationRunning`). A lock asked
    /// for meanwhile (window hidden, idle timer) is applied as soon as the operation ends, so
    /// no operation ever continues on a journal or Keychain state that changed under it.
    @MainActor
    func performKeyOperation<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        guard !isKeyOperationRunning else { throw AppLockVault.VaultError.busy }
        isKeyOperationRunning = true
        defer {
            isKeyOperationRunning = false
            if isLockRequested {
                isLockRequested = false
                lock()
            }
        }
        return try await operation()
    }

    // MARK: - Unlocking

    /// Check the password, unwrap the key, then decrypt and open the journal.
    /// - Parameter acceptOlderJournal: the owner confirmed opening a journal older than the
    ///   last one this Mac saved (they typed the password again for that)
    @MainActor
    func unlock(password: String, acceptOlderJournal: Bool = false) async -> UnlockResult {
        do {
            return try await performKeyOperation {
                await unlockNow(password: password, acceptOlderJournal: acceptOlderJournal)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func unlockNow(password: String, acceptOlderJournal: Bool) async -> UnlockResult {
        guard isLocked else { return .unlocked }
        let vault = self.vault
        let mayCreate = !encryptedJournalExists
        let check = Task.detached(priority: .userInitiated) { () -> Result<AppLockVault.UnlockKeys, Error> in
            Result { try vault.unlockKeys(password: password, mayCreateKey: mayCreate) }
        }
        await hooks.whileUnlocking?()
        let outcome = await check.value
        guard isLocked else { return .unlocked }
        let keys: AppLockVault.UnlockKeys
        switch outcome {
        case .success(let found):
            keys = found
        case .failure(let error as AppLockVault.VaultError) where error == .wrongPassword:
            Self.logger.notice("App Lock: wrong password")
            return .wrongPassword
        case .failure(let error as AppLockVault.VaultError) where error == .notLocked:
            return openWithoutLock()
        case .failure(let error):
            return .failed(error.localizedDescription)
        }

        var opened: (DatabaseManager, SymmetricKey)?
        let candidates = ([keys.primary].compactMap { $0 } + keys.fallbacks).map { SymmetricKey(data: $0) }
        if let held = heldJournal, let key = held.encryptionKey {
            // The last lock couldn't save: its journal (with the unsaved changes) is still in
            // memory. Use it rather than the older file on disk.
            reinstallHeldJournal(held)
            opened = (held, key)
        } else {
            // Try the current key, then what an interrupted key rotation left behind
            for key in candidates {
                do {
                    opened = (try openManager(key: key, acceptOlder: acceptOlderJournal), key)
                    break
                } catch let older as DatabaseManager.OlderJournal {
                    holdOlderJournal(older)
                    return .olderJournal
                } catch let error where !DatabaseManager.isUnreadable(error) {
                    // The disk or the folder failed, not the key: never set the file aside for that
                    Self.logger.error("Unlock: the journal couldn't be read; left untouched")
                    return .failed(Self.openFailureMessage(error))
                } catch {
                    continue
                }
            }
            if let (manager, _) = opened { install(manager) }
        }
        if let (manager, key) = opened {
            do {
                if let primary = keys.primary.map({ SymmetricKey(data: $0) }) {
                    // Finish an interrupted rotation: re-seal with the current key, and let the
                    // old keys go only once the file on disk and every screenshot open with it
                    if AppLockVault.raw(key) != AppLockVault.raw(primary) {
                        try manager.rekey(to: primary)
                        guard manager.fileOpens(with: primary) else {
                            throw DatabaseManager.StorageError.serializationFailed
                        }
                    }
                    let olds = candidates.filter { AppLockVault.raw($0) != AppLockVault.raw(primary) }
                    if await resealScreenshots(from: olds, to: primary).isEmpty {
                        vault.finishUnlock(primary: primary)
                    } else {
                        // Their old key stays stored; the next key change or unlock tries again
                        pendingScreenshotKeys = olds.map(AppLockVault.raw)
                        Self.logger.error("Unlock: some screenshots still need an older key; it stays stored")
                    }
                } else if keys.needsRotation {
                    // Install from before key wrapping: move to a new, wrapped key
                    _ = try await rotateKey(password: password)
                }
            } catch {
                Self.logger.error("Finishing the key change failed: \(error.localizedDescription)")
            }
        } else if let first = candidates.first {
            // No key we hold opens it: set it aside (still encrypted) and start fresh
            guard openJournal(key: first) else { return .failed(databaseError ?? "") }
        } else {
            return .failed(AppLockVault.VaultError.keyUnavailable.localizedDescription)
        }
        olderJournal = nil
        // Unlocked with the lock password: the lock is on (kept in memory, so locking never
        // depends on reading the Keychain at that moment)
        isAppLockEnabled = true
        keychainUnreadableAtLaunch = false
        isLocked = false
        screenshotsBecameReadable()
        vault.throttle.reset() // the right password: the wrong-password count starts over
        Self.logger.notice("App Lock: unlocked")
        return .unlocked
    }

    /// The lock screen is up but the Keychain says no lock item exists any more (errSecItemNotFound
    /// for both; a read error never gets here): there is no password to check, so open the
    /// journal the way a launch without App Lock does instead of leaving a lock screen nobody
    /// can pass. The wrong-password count is left as it is. Never while a journal is held
    /// (`heldJournal`, decrypted in memory since a lock): that one only comes back with the
    /// password or the owner's recovery, so Greenwick stays locked.
    @MainActor
    private func openWithoutLock() -> UnlockResult {
        guard heldJournal == nil else {
            Self.logger.error("App Lock items gone while a journal is held: staying locked")
            return .failed(AppLockVault.VaultError.keychainUnreadable.localizedDescription)
        }
        Self.logger.notice("App Lock is off in the Keychain: opening without the lock screen")
        isAppLockEnabled = false
        olderJournal = nil
        keychainUnreadableAtLaunch = false
        openJournalWithPlainKey()
        isLocked = false
        screenshotsBecameReadable()
        return .unlocked
    }

    // MARK: - Older journal (rollback)

    /// The journal on disk is older than the last one this Mac saved: keep it closed and
    /// untouched until the owner confirms
    func holdOlderJournal(_ older: DatabaseManager.OlderJournal) {
        olderJournal = older
        Self.logger.notice("Journal older than the last one saved on this Mac: waiting for the owner")
    }

    /// App Lock off: the owner explicitly confirmed opening the older journal. The Keychain
    /// record then follows the file. (With App Lock on, `unlock(password:acceptOlderJournal:)`
    /// does this after the password.) Returns whether the journal opened.
    @MainActor
    @discardableResult
    func openOlderJournal() -> Bool {
        guard olderJournal != nil, !isAppLockEnabled else { return false }
        do {
            let key = try vault.plainKey(createIfMissing: false)
            install(try openManager(key: key, acceptOlder: true))
            screenshotsBecameReadable()
            olderJournal = nil
            Self.logger.notice("Owner opened a journal older than the last one saved on this Mac")
            return true
        } catch {
            Self.logger.error("Opening the older journal failed: \(error.localizedDescription)")
            databaseError = "Greenwick couldn't open this journal: \(error.localizedDescription)"
            return false
        }
    }

    /// The owner chose not to open the older journal (App Lock on): back to the lock screen
    func dismissOlderJournal() {
        olderJournal = nil
    }

    // MARK: - Locking

    /// Lock now: show the lock screen, then save, close and forget the key. While a key
    /// operation runs, the lock waits for it to finish (`performKeyOperation`).
    @MainActor
    func lock() {
        guard !isKeyOperationRunning else {
            isLockRequested = true
            return
        }
        guard isAppLockEnabled, !isLocked else { return }
        isLocked = true
        // From now on no screenshot is decrypted or written (waits for one being written)
        screenshots.useKey(nil)
        pendingScreenshotKeys = []
        // An app-modal panel (e.g. the backup save/open panel) would stay on top of the lock
        // screen: end it; its runModal returns without a choice, so nothing is written or
        // restored. SwiftUI sheets and alerts go away with the journal views they belong to.
        if NSApp?.modalWindow != nil { NSApp?.abortModal() }
        // Let the journal views go away before the database closes under them
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.closeJournal()
        }
    }
}
