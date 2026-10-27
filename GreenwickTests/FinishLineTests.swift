import AppKit
import XCTest
@testable import Greenwick

/// Finish-line review (F1–F4): a lock during the quit dialog, a held journal with the lock
/// items gone, Keychain read errors in the wrong-password limit, and a Keychain that can't be
/// read at launch with App Lock off.
@MainActor
final class FinishLineTests: XCTestCase {
    private let password = "correct-horse-42"

    private func makeState(_ vault: AppLockVault, _ folder: URL, writer: JournalFileWriter = .secure) -> AppState {
        AppState(vault: vault, databasePath: journal(folder).path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true),
                 journalWriter: writer)
    }

    private func journal(_ folder: URL) -> URL { folder.appendingPathComponent("Greenwick.sqlite") }

    /// Let a lock's close Task run
    private func closeWait(_ state: AppState) async {
        for _ in 0..<50 where state.database.isPersistent { await Task.yield() }
    }

    private func extraTrade() -> Trade {
        var extra = sampleTrades()[0]
        extra.ticket = 77
        return extra
    }

    /// App Lock on, unlocked, a full disk and one change that exists only in memory
    private func unsavedChange(_ vault: AppLockVault, _ folder: URL, _ disk: FlakyDisk) async throws -> AppState {
        let state = makeState(vault, folder, writer: disk.writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        _ = try await state.enableAppLock(password: password)
        disk.isFull = true
        XCTAssertEqual(try state.tradeRepository.bulkInsert([extraTrade()]), 1)
        XCTAssertNotNil(state.database.lastSaveError, "Setup: the change is only in memory")
        return state
    }

    // MARK: - F1: a lock during the quit dialog

    /// Quitting with unsaved changes shows Try Again / Quit Anyway. The idle lock fires while
    /// it is open and ends it (`abortModal`: the alert returns `.abort`). Before the fix that
    /// counted as Quit Anyway and the change was dropped. Now Greenwick stays open and locked,
    /// with the change held in memory; the next quit asks again.
    func testLockDuringTheQuitDialogDoesNotQuit() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let disk = FlakyDisk()
        let state = try await unsavedChange(vault, folder, disk)

        var asked = 0
        let reply = AppDelegate.replyToQuit(state) { _ in
            asked += 1
            state.lock()
            return .abort
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(reply, .terminateCancel, "Nobody chose Quit Anyway: don't quit")
        await closeWait(state)
        XCTAssertTrue(state.isLocked)
        XCTAssertNotNil(state.heldJournal, "The unsaved change is kept behind the lock screen")
        XCTAssertNotNil(state.saveBeforeQuit(), "The next quit asks again")

        // The owner's own answers still work: Quit Anyway quits, Try Again saves first
        XCTAssertEqual(AppDelegate.replyToQuit(state) { _ in .alertSecondButtonReturn }, .terminateNow)
        disk.isFull = false
        XCTAssertEqual(AppDelegate.replyToQuit(state) { _ in .alertFirstButtonReturn }, .terminateNow)
        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 31, "Nothing was lost")
        state.shutdown()
    }

    // MARK: - F2: a held journal never comes back without the password

    /// The final save at lock failed, so the journal waits decrypted in memory. Someone then
    /// deletes the lock items from the Keychain. Before the fix ANY password got "no lock any
    /// more" and the held journal was shown. Now Greenwick stays locked and keeps it.
    func testHeldJournalStaysLockedWhenTheLockItemsDisappear() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let disk = FlakyDisk()
        let state = try await unsavedChange(vault, folder, disk)
        state.lock()
        await closeWait(state)
        XCTAssertNotNil(state.heldJournal, "Setup: the journal is held")

        store.delete(AppLockVault.Account.wrappedKey)
        store.delete(AppLockVault.Account.legacyHash)
        let result = await state.unlock(password: "not-the-password")
        XCTAssertEqual(result, .failed(AppLockVault.VaultError.keychainUnreadable.localizedDescription))
        XCTAssertTrue(state.isLocked)
        XCTAssertFalse(state.database.isPersistent, "Nothing shown")
        XCTAssertNotNil(state.heldJournal, "Still held, not dropped")
        XCTAssertNotNil(state.saveBeforeQuit(), "Quitting still asks first")
        state.shutdown()
    }

    // MARK: - F3: the wrong-password limit fails closed

    /// A throttle item that exists but can't be read. Before the fix that read as "no wait"
    /// and a wrong password rewrote the count as 1. Now no password may be checked meanwhile
    /// (`keychainUnreadable`) and the stored count and wait are never overwritten.
    func testUnreadableThrottleNeverResetsTheCountOrTheWait() throws {
        let store = MemorySecretStore()
        let clock = TestClock()
        var throttle = UnlockThrottle(store: store)
        throttle.now = { clock.now }
        for _ in 1...5 { _ = try throttle.recordFailure() }
        XCTAssertEqual(throttle.remainingLockout, 30, "Setup: waiting")
        let stored = (store.read(UnlockThrottle.attemptsAccount), store.read(UnlockThrottle.lockoutUntilAccount))

        for account in [UnlockThrottle.attemptsAccount, UnlockThrottle.lockoutUntilAccount] {
            store.failReads(of: [account])
            XCTAssertThrowsError(try throttle.checkAllowed(), account) { error in
                XCTAssertEqual(error as? AppLockVault.VaultError, .keychainUnreadable, account)
            }
            XCTAssertThrowsError(try throttle.recordFailure(), account)
            store.failReads(of: [])
            XCTAssertEqual(store.read(UnlockThrottle.attemptsAccount), stored.0, "Count untouched: \(account)")
            XCTAssertEqual(store.read(UnlockThrottle.lockoutUntilAccount), stored.1, "Wait untouched: \(account)")
        }
        XCTAssertEqual(throttle.failedAttempts, 5)

        // Readable again, wait over: one more wrong password is number 6
        clock.advance(31)
        XCTAssertNoThrow(try throttle.checkAllowed())
        XCTAssertEqual(try throttle.recordFailure().attempts, 6)
    }

    /// Settings' Change Password / Turn Off: an unreadable count refuses the check too
    func testSettingsPasswordCheckRefusedWhileTheCountCantBeRead() async throws {
        let folder = try makeScratchFolder()
        var (vault, _, _) = makeVault()
        let throttleStore = MemorySecretStore()
        vault.throttle = UnlockThrottle(store: throttleStore)
        let state = makeState(vault, folder)
        _ = try await state.enableAppLock(password: password)
        for _ in 1...3 { _ = try vault.throttle.recordFailure() }

        throttleStore.failReads(of: [UnlockThrottle.attemptsAccount])
        do {
            try await state.checkLockPassword("wrong-password-1")
            XCTFail("No password may be checked while the count can't be read")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .keychainUnreadable)
        }
        throttleStore.failReads(of: [])
        XCTAssertEqual(vault.throttle.failedAttempts, 3, "Count untouched")
        state.shutdown()
    }

    // MARK: - F4: Keychain unreadable at launch with App Lock off

    /// App Lock is off, but at launch the Keychain can't be read (e.g. the login keychain is
    /// still locked). Greenwick fails closed and shows the lock screen. Before the fix it said
    /// nothing until a password was typed, and "Forgot Password?" erased the journal (then
    /// failed to start a new one anyway). Now the lock screen says why at once, and Erase is
    /// refused (no prompt, nothing deleted) while the reads fail.
    func testUnreadableKeychainAtLaunchExplainsAndRefusesErase() async throws {
        let folder = try makeScratchFolder()
        let owner = MemoryOwnerCheck()
        let (vault, store, _) = makeVault(presenceSupported: false, owner: owner)
        let first = makeState(vault, folder)
        XCTAssertEqual(try first.tradeRepository.bulkInsert(sampleTrades()), 30)
        first.shutdown()
        let onDisk = try Data(contentsOf: journal(folder))

        store.failReads(of: [AppLockVault.Account.wrappedKey])
        let state = makeState(vault, folder)
        XCTAssertTrue(state.isLocked, "Fail closed")
        XCTAssertTrue(state.keychainUnreadableAtLaunch, "The lock screen explains at once")
        do {
            try await state.eraseAllLocalData()
            XCTFail("Erase must be refused while the Keychain can't be read")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .keychainUnreadable)
        }
        XCTAssertEqual(owner.prompts, 0, "Not even asked")
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk, "Journal untouched")
        XCTAssertTrue(state.isLocked)

        // Same while the plain key can't be read
        store.failReads(of: [AppLockVault.Account.plainKey])
        do {
            try await state.eraseAllLocalData()
            XCTFail("Erase must be refused while the journal key can't be read")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .keychainUnreadable)
        }
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)

        // Readable again: any password re-checks, and the journal opens like a lock-off launch
        store.failReads(of: [])
        let result = await state.unlock(password: "anything-at-all")
        XCTAssertEqual(result, .unlocked)
        XCTAssertFalse(state.keychainUnreadableAtLaunch)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }
}
