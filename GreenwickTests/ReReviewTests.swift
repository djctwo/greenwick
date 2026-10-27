import CryptoKit
import XCTest
@testable import Greenwick

/// Re-review: App Lock operations that overlap (one at a time, a lock waits for them),
/// unsaved changes at lock and quit, Erase that can't delete the journal, and Keychain read
/// errors. Overlaps are made deterministic with `AppState.hooks`, which run while the
/// password check or the key wrapping is still running off the main thread.
@MainActor
final class ReReviewTests: XCTestCase {
    private let password = "correct-horse-42"
    private let newPassword = "another-pass-1"

    /// Holds what a hook saw (hooks are `@MainActor` closures)
    private final class Seen {
        var error: Error?
        var unlock: AppState.UnlockResult?
    }

    private func makeState(_ vault: AppLockVault, _ folder: URL, writer: JournalFileWriter = .secure) -> AppState {
        AppState(vault: vault, databasePath: journal(folder).path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true),
                 journalWriter: writer)
    }

    private func journal(_ folder: URL) -> URL { folder.appendingPathComponent("Greenwick.sqlite") }

    /// What `lock()` does when the window goes to the background, run to completion
    private func lockAndWait(_ state: AppState?) async {
        state?.lock()
        await closeWait(state)
    }

    /// Let a lock's close Task run
    private func closeWait(_ state: AppState?) async {
        for _ in 0..<50 where state?.database.isPersistent == true { await Task.yield() }
    }

    /// A lock-on journal with the 30 sample trades, locked
    private func lockedJournal(_ vault: AppLockVault, _ folder: URL,
                               writer: JournalFileWriter = .secure) async throws -> AppState {
        let state = makeState(vault, folder, writer: writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        _ = try await state.enableAppLock(password: password)
        await lockAndWait(state)
        XCTAssertTrue(state.isLocked, "Setup: locked")
        return state
    }

    private func extraTrade() -> Trade {
        var extra = sampleTrades()[0]
        extra.ticket = 77
        return extra
    }

    // MARK: - N1: Forgot Password while an unlock runs

    /// Signed build. "Forgot Password? > Reset" while the unlock checks the password. Before
    /// the fix the recovery removed the lock, then the unlock carried on with keys read
    /// before it and deleted the plain key the recovery had just written: the journal was
    /// left with no key the app could reach. Now recovery waits its turn (refused, nothing
    /// asked or changed) and the unlock finishes normally.
    func testForgotPasswordDuringAnUnlockIsRefused() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, presence) = makeVault()
        let state = try await lockedJournal(vault, folder)
        let seen = Seen()
        state.hooks.whileUnlocking = { [weak state] in
            do { try await state?.recoverWithDeviceOwner() } catch { seen.error = error }
        }

        let result = await state.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(seen.error as? AppLockVault.VaultError, .busy)
        XCTAssertEqual(presence.prompts, 0, "Touch ID / Mac password never asked")
        XCTAssertTrue(state.isAppLockEnabled)
        XCTAssertTrue(vault.isLockEnabled)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        XCTAssertTrue(relaunched.isLocked)
        let again = await relaunched.unlock(password: password)
        XCTAssertEqual(again, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Unsigned build: "Erase All Local Data" while the unlock checks the password is refused
    /// before the owner is even asked, and the journal and keys stay
    func testEraseDuringAnUnlockIsRefused() async throws {
        let folder = try makeScratchFolder()
        let owner = MemoryOwnerCheck()
        let (vault, _, _) = makeVault(presenceSupported: false, owner: owner)
        let state = try await lockedJournal(vault, folder)
        let seen = Seen()
        state.hooks.whileUnlocking = { [weak state] in
            do { try await state?.eraseAllLocalData() } catch { seen.error = error }
        }

        let result = await state.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(seen.error as? AppLockVault.VaultError, .busy)
        XCTAssertEqual(owner.prompts, 0)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let again = await relaunched.unlock(password: password)
        XCTAssertEqual(again, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    // MARK: - N2: a lock asked for during an unlock or during Enable

    /// The window is hidden right after Unlock was pressed. Before the fix the lock was a
    /// no-op (still locked) and the unlock then left Greenwick open while hidden. Now the
    /// lock is applied as soon as the unlock finishes.
    func testLockDuringAnUnlockIsAppliedAfterIt() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try await lockedJournal(vault, folder)
        state.hooks.whileUnlocking = { [weak state] in state?.lock() }

        let result = await state.unlock(password: password)
        XCTAssertEqual(result, .unlocked, "The password was right")
        XCTAssertTrue(state.isLocked, "The requested lock followed")
        await closeWait(state)
        XCTAssertFalse(state.database.isPersistent, "Journal closed, key forgotten")

        state.hooks = AppState.Hooks()
        let again = await state.unlock(password: password)
        XCTAssertEqual(again, .unlocked)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    /// The window is hidden while Enable App Lock wraps the new key (the lock isn't on yet).
    /// Before the fix that lock was dropped; now it follows once the lock is on.
    func testLockDuringEnableIsAppliedAfterIt() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        state.hooks.whileRotationBegins = { [weak state] in state?.lock() }

        let change = try await state.enableAppLock(password: password)
        XCTAssertEqual(change, .done(hasRecovery: true))
        XCTAssertTrue(state.isLocked)
        await closeWait(state)
        XCTAssertFalse(state.database.isPersistent)

        state.hooks = AppState.Hooks()
        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    // MARK: - N5: lock and unlock inside a password change

    /// The window is hidden and Unlock tried while a password change wraps the new key.
    /// Before the fix the lock closed the journal and an unlock with the old password could
    /// delete the old key the change still needed: the journal was sealed with a key stored
    /// nowhere. Now the lock waits, the unlock is refused, and the change completes first.
    func testLockAndUnlockDuringAPasswordChangeWaitForIt() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        _ = try await state.enableAppLock(password: password)
        let seen = Seen()
        state.hooks.whileRotationBegins = { [weak state] in
            state?.lock()
            XCTAssertEqual(state?.isLocked, false, "The lock waits for the change")
            seen.unlock = await state?.unlock(password: self.password)
        }

        let change = try await state.changeAppLockPassword(current: password, new: newPassword)
        XCTAssertEqual(change, .done(hasRecovery: true))
        XCTAssertEqual(seen.unlock, .failed(AppLockVault.VaultError.busy.localizedDescription))
        XCTAssertTrue(state.isLocked, "The requested lock followed")
        await closeWait(state)
        XCTAssertEqual(try vault.unlockKeys(password: newPassword, mayCreateKey: false).fallbacks, [],
                       "Only the new key is stored")

        state.hooks = AppState.Hooks()
        let old = await state.unlock(password: password)
        XCTAssertEqual(old, .wrongPassword)
        let new = await state.unlock(password: newPassword)
        XCTAssertEqual(new, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let again = await relaunched.unlock(password: newPassword)
        XCTAssertEqual(again, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    // MARK: - N3: unsaved changes at lock and quit

    /// Full disk: a change is only in memory, then Greenwick locks. Before the fix the failed
    /// final save still closed the journal and the change was gone after unlock, without a
    /// word. Now the journal waits in memory behind the lock screen and comes back at unlock
    /// (saved again as soon as the disk has room).
    func testLockAfterAFailedSaveKeepsTheChanges() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let disk = FlakyDisk()
        let state = try await lockedJournal(vault, folder, writer: disk.writer)
        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)

        disk.isFull = true
        XCTAssertEqual(try state.tradeRepository.bulkInsert([extraTrade()]), 1)
        XCTAssertNotNil(state.database.lastSaveError, "Setup: the change is only in memory")
        await lockAndWait(state)
        XCTAssertTrue(state.isLocked)
        XCTAssertFalse(state.database.isPersistent, "Nothing is shown behind the lock screen")
        XCTAssertNotNil(state.saveBeforeQuit(), "Quitting now would lose the change: Greenwick asks")

        // Still full at unlock: the change is back, and the alert says it isn't saved yet
        let stillFull = await state.unlock(password: password)
        XCTAssertEqual(stillFull, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 31)
        XCTAssertTrue(try XCTUnwrap(state.databaseError).contains("couldn't save your journal"))

        await lockAndWait(state)
        disk.isFull = false
        let roomAgain = await state.unlock(password: password)
        XCTAssertEqual(roomAgain, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 31)
        XCTAssertNil(state.database.lastSaveError, "Saved again at unlock")
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let again = await relaunched.unlock(password: password)
        XCTAssertEqual(again, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 31, "The change reached the disk")
        relaunched.shutdown()
    }

    /// Quitting with a change that couldn't be saved: Greenwick asks first (Try Again / Quit
    /// Anyway) and keeps the change while asking; Try Again saves it once the disk has room
    func testQuitAfterAFailedSaveAsksFirst() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let disk = FlakyDisk()
        let state = makeState(vault, folder, writer: disk.writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        XCTAssertNil(state.saveBeforeQuit(), "Everything saved: quit without asking")

        disk.isFull = true
        XCTAssertEqual(try state.tradeRepository.bulkInsert([extraTrade()]), 1)
        XCTAssertNotNil(state.saveBeforeQuit(), "Still failing: ask")
        XCTAssertEqual(try state.tradeRepository.count(), 31, "Asking drops nothing")
        disk.isFull = false
        XCTAssertNil(state.saveBeforeQuit(), "Try Again saved it")
        state.shutdown()

        let relaunched = makeState(vault, folder)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 31)
        relaunched.shutdown()
    }

    // MARK: - N4: Erase that can't delete the journal

    /// The journal file can't be deleted (folder not writable). Before the fix every key was
    /// removed anyway, leaving a sealed file no key opens and an app that failed at every
    /// launch. Now Erase stops, says why, and keeps the keys: the password still unlocks.
    func testEraseThatCantDeleteTheJournalKeepsEveryKey() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault(presenceSupported: false)
        let state = try await lockedJournal(vault, folder)
        let keys = store.accounts
        let onDisk = try Data(contentsOf: journal(folder))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }

        do {
            try await state.eraseAllLocalData()
            XCTFail("The journal is still there: nothing may be erased")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .journalNotDeleted)
        }
        XCTAssertEqual(store.accounts, keys, "Every key kept")
        XCTAssertTrue(state.isLocked)
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    // MARK: - N6: Keychain read errors fail closed

    /// Turning the lock on couldn't re-encrypt yet (the old lock-off key is still stored),
    /// and then the wrapped key can't be read (locked keychain, refused access prompt).
    /// Before the fix that read error counted as "no lock": ANY password opened the journal
    /// and the wrong-password count was reset. Now it stays locked and says why.
    func testUnreadableLockKeyNeverOpensWithoutThePassword() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let disk = FlakyDisk()
        let state = makeState(vault, folder, writer: disk.writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        disk.isFull = true
        let change = try await state.enableAppLock(password: password)
        XCTAssertEqual(change, .finishesAtNextUnlock, "Setup: the lock-off key is still stored")
        disk.isFull = false
        await lockAndWait(state)
        for _ in 1...2 { _ = try vault.throttle.recordFailure() }

        store.failReads(of: [AppLockVault.Account.wrappedKey])
        let result = await state.unlock(password: "not-the-password")
        XCTAssertEqual(result, .failed(AppLockVault.VaultError.keychainUnreadable.localizedDescription))
        XCTAssertTrue(state.isLocked)
        XCTAssertTrue(state.isAppLockEnabled)
        XCTAssertFalse(state.database.isPersistent, "Nothing decrypted")
        XCTAssertEqual(vault.throttle.failedAttempts, 2, "Count unchanged")

        store.failReads(of: [])
        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertEqual(vault.throttle.failedAttempts, 0, "The right password resets the count")
        state.shutdown()
    }

    /// At launch, a lock item that can't be read means "locked" (the lock screen shows),
    /// never "lock off" (the journal opened with whatever plain key is stored)
    func testUnreadableLockItemAtLaunchShowsTheLockScreen() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let disk = FlakyDisk()
        let state = makeState(vault, folder, writer: disk.writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        disk.isFull = true
        _ = try await state.enableAppLock(password: password)
        disk.isFull = false
        state.shutdown()

        for account in [AppLockVault.Account.wrappedKey, AppLockVault.Account.legacyHash] {
            store.failReads(of: [account])
            XCTAssertTrue(vault.isLockEnabled, account)
            let relaunched = makeState(vault, folder)
            XCTAssertTrue(relaunched.isLocked, account)
            XCTAssertFalse(relaunched.database.isPersistent, "Nothing decrypted: \(account)")
            relaunched.shutdown()
        }
    }

    /// A plain key that exists but can't be read is never replaced by a new one (older
    /// set-aside copies sealed with it would become undecryptable)
    func testUnreadablePlainKeyIsNeverReplaced() throws {
        let (vault, store, _) = makeVault()
        let key = try vault.plainKey(createIfMissing: true)
        let stored = store.read(AppLockVault.Account.plainKey)

        store.failReads(of: [AppLockVault.Account.plainKey])
        XCTAssertThrowsError(try vault.plainKey(createIfMissing: true))
        store.failReads(of: [])
        XCTAssertEqual(store.read(AppLockVault.Account.plainKey), stored)
        XCTAssertEqual(AppLockVault.raw(try vault.plainKey(createIfMissing: false)), AppLockVault.raw(key))
    }
}
