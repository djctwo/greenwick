import CryptoKit
import XCTest
@testable import Greenwick

/// Final review: App Lock changes that race a lock, interrupted password changes and the
/// recovery copy, and the wrong-password limit in Settings. Races are made deterministic
/// with `AppState.hooks`, which run exactly where an `await` lets a lock in.
@MainActor
final class KeyChangeRaceTests: XCTestCase {
    private let password = "correct-horse-42"
    private let newPassword = "another-pass-1"

    private func makeState(_ vault: AppLockVault, _ folder: URL, writer: JournalFileWriter = .secure) -> AppState {
        AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true),
                 journalWriter: writer)
    }

    private func journalOpens(_ folder: URL, with key: SymmetricKey) -> Bool {
        guard let sealed = try? Data(contentsOf: folder.appendingPathComponent("Greenwick.sqlite")) else { return false }
        return (try? JournalFormat.open(sealed, key: key)) != nil
    }

    /// What `lock()` does when the window goes to the background, run to completion
    private func lockAndWait(_ state: AppState?) async {
        state?.lock()
        for _ in 0..<50 where state?.database.isPersistent == true { await Task.yield() }
    }

    /// A lock-on journal with the 30 sample trades
    private func lockedOnState(_ vault: AppLockVault, _ folder: URL,
                               writer: JournalFileWriter = .secure) async throws -> AppState {
        let state = makeState(vault, folder, writer: writer)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        _ = try await state.enableAppLock(password: password)
        return state
    }

    // MARK: - Finding 1: password change racing a quit

    /// Greenwick quits (closing the journal) while the new password is being wrapped. The
    /// final save seals the file with the OLD key, so the old key must survive; the next
    /// unlock with the new password finishes the change. Before the fix the old key was
    /// deleted and the journal set aside as unreadable. (A lock during a key change now waits
    /// for it: `ReReviewTests`.)
    func testPasswordChangeRacingAQuitKeepsTheJournal() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try await lockedOnState(vault, folder)
        let oldKey = try XCTUnwrap(state.database.encryptionKey)
        state.hooks.afterRotationBegan = { [weak state] in state?.shutdown() }

        let change = try await state.changeAppLockPassword(current: password, new: newPassword)
        XCTAssertEqual(change, .finishesAtNextUnlock)
        XCTAssertFalse(state.database.isPersistent, "Closed by quitting")
        XCTAssertTrue(journalOpens(folder, with: oldKey), "The final save used the old key")
        let pending = try vault.unlockKeys(password: newPassword, mayCreateKey: false)
        XCTAssertEqual(pending.fallbacks, [AppLockVault.raw(oldKey)], "The old key is still stored")

        let relaunched = makeState(vault, folder)
        let wrong = await relaunched.unlock(password: password)
        XCTAssertEqual(wrong, .wrongPassword, "The new password is in force")
        let unlocked = await relaunched.unlock(password: newPassword)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        let newKey = try XCTUnwrap(relaunched.database.encryptionKey)
        XCTAssertTrue(journalOpens(folder, with: newKey), "Finished at unlock: re-sealed with the new key")
        XCTAssertFalse(journalOpens(folder, with: oldKey))
        XCTAssertEqual(try vault.unlockKeys(password: newPassword, mayCreateKey: false).fallbacks, [])
        try assertOnlyTheJournal(in: folder)
        relaunched.shutdown()
    }

    /// A manager that is closed (or only in memory) can't be re-sealed: `rekey` throws
    /// instead of returning as if it had worked
    func testRekeyRefusesAClosedOrInMemoryJournal() throws {
        let folder = try makeScratchFolder()
        let manager = try DatabaseManager(path: folder.appendingPathComponent("Greenwick.sqlite").path,
                                          key: SymmetricKey(size: .bits256))
        manager.close()
        XCTAssertThrowsError(try manager.rekey(to: SymmetricKey(size: .bits256)))
        XCTAssertThrowsError(try DatabaseManager(inMemory: true).rekey(to: SymmetricKey(size: .bits256)))
    }

    // MARK: - Dojix #3: a failed re-seal must not be reported as "nothing changed"

    /// Turning the lock on or changing the password when the journal can't be re-sealed
    /// (full disk): the new password is already the one that unlocks, so the change reports
    /// `.finishesAtNextUnlock` instead of an error, and the next unlock completes it.
    func testFailedReSealStillReportsTheNewPassword() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let disk = FlakyDisk()
        let state = makeState(vault, folder, writer: disk.writer)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())

        disk.isFull = true
        let enabled = try await state.enableAppLock(password: password)
        XCTAssertEqual(enabled, .finishesAtNextUnlock)
        XCTAssertTrue(state.isAppLockEnabled, "The lock is on: the app must show it and lock")
        XCTAssertTrue(vault.isLockEnabled)

        let changed = try await state.changeAppLockPassword(current: password, new: newPassword)
        XCTAssertEqual(changed, .finishesAtNextUnlock)
        disk.isFull = false
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let old = await relaunched.unlock(password: password)
        XCTAssertEqual(old, .wrongPassword)
        let new = await relaunched.unlock(password: newPassword)
        XCTAssertEqual(new, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        let key = try XCTUnwrap(relaunched.database.encryptionKey)
        XCTAssertTrue(journalOpens(folder, with: key))
        relaunched.shutdown()
    }

    // MARK: - Finding 5: Turn Off racing a lock or a quit

    /// The app is asked to lock while Turn Off checks the password. Before the fix the lock
    /// was removed under the lock screen, which then refused every password ("App lock is not
    /// turned on"). Now the lock waits for Turn Off: the lock ends up off, the journal open,
    /// and no lock screen nobody can pass.
    func testLockDuringTurnOffWaitsForIt() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try await lockedOnState(vault, folder)
        state.hooks.afterDisablePasswordCheck = { [weak state] in
            state?.lock()
            XCTAssertEqual(state?.isLocked, false, "The lock waits for Turn Off")
        }

        try await state.disableAppLock(password: password)
        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.isAppLockEnabled)
        XCTAssertFalse(vault.isLockEnabled)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        XCTAssertFalse(relaunched.isLocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Greenwick quits (closing the journal) while Turn Off checks the password: nothing
    /// changes, and the password still unlocks it at the next launch
    func testTurnOffRacingAQuitChangesNothing() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try await lockedOnState(vault, folder)
        state.hooks.afterDisablePasswordCheck = { [weak state] in state?.shutdown() }

        do {
            try await state.disableAppLock(password: password)
            XCTFail("The journal closed meanwhile: nothing may change")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .lockedMeanwhile)
        }
        XCTAssertTrue(state.isAppLockEnabled)
        XCTAssertTrue(vault.isLockEnabled)

        let relaunched = makeState(vault, folder)
        XCTAssertTrue(relaunched.isLocked)
        let unlocked = await relaunched.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Belt and braces: a lock screen showing while the Keychain has no lock any more opens
    /// the journal the way a launch without App Lock would, instead of trapping the user
    func testLockScreenOpensWhenTheLockIsAlreadyOff() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try await lockedOnState(vault, folder)
        let key = try XCTUnwrap(state.database.encryptionKey)
        await lockAndWait(state)
        try vault.removeLock(keeping: key)
        for _ in 1...2 { _ = try vault.throttle.recordFailure() }

        let result = await state.unlock(password: "anything-at-all")
        XCTAssertEqual(result, .unlocked)
        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.isAppLockEnabled)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertEqual(vault.throttle.failedAttempts, 2, "No password was checked: the count stays")
        state.shutdown()
    }

    // MARK: - Finding 4: recovery copy after an interrupted password change

    /// Interrupted after step 2 (file re-sealed with the new key, recovery copy still on the
    /// old one) and stopped. Unlocking with the new password must replace the recovery copy;
    /// before the fix it was only written when missing, so it stayed outdated for good.
    func testUnlockReplacesAnOutdatedRecoveryCopy() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, presence) = makeVault()
        let (_, newKey) = try await interruptedPasswordChange(vault, folder)

        let relaunched = makeState(vault, folder)
        let result = await relaunched.unlock(password: newPassword)
        XCTAssertEqual(result, .unlocked)
        let copy = await presence.retrieve(reason: "t")
        XCTAssertEqual(copy, AppLockVault.raw(newKey), "The recovery copy follows the key that opens the journal")
        XCTAssertEqual(vault.store.read(AppLockVault.Account.recoveryFingerprint), AppLockVault.fingerprint(newKey))
        relaunched.shutdown()
    }

    /// Same interruption, then "Forgot Password?": the outdated copy can't open the journal.
    /// That must say so (and the lock screen then offers erasing) and change nothing; before
    /// the fix it was a generic error and only "Reset" was ever offered.
    func testRecoveryWithAnOutdatedCopySaysSoAndChangesNothing() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        _ = try await interruptedPasswordChange(vault, folder)
        let path = folder.appendingPathComponent("Greenwick.sqlite")
        let onDisk = try Data(contentsOf: path)

        let relaunched = makeState(vault, folder)
        do {
            try await relaunched.recoverWithDeviceOwner()
            XCTFail("The outdated copy can't open the journal")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .recoveryKeyOutdated)
        }
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertTrue(vault.isLockEnabled)
        XCTAssertEqual(try Data(contentsOf: path), onDisk, "Journal untouched")
        let unlocked = await relaunched.unlock(password: newPassword)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Lock on, then a password change stopped after step 2: returns (old key, new key)
    private func interruptedPasswordChange(_ vault: AppLockVault,
                                           _ folder: URL) async throws -> (SymmetricKey, SymmetricKey) {
        let state = try await lockedOnState(vault, folder)
        let current = try XCTUnwrap(state.database.encryptionKey)
        let newKey = SymmetricKey(size: .bits256)
        try vault.beginRotation(to: newKey, password: newPassword, current: current)  // step 1
        try state.database.rekey(to: newKey)                                           // step 2
        state.shutdown()                                                               // stop
        let copy = await vault.presence.retrieve(reason: "t")
        XCTAssertEqual(copy, AppLockVault.raw(current), "Setup: the recovery copy is outdated")
        return (current, newKey)
    }

    // MARK: - Dojix #7: wrong passwords in Settings count toward the lockout

    func testPasswordChecksInSettingsShareTheLockout() async throws {
        let folder = try makeScratchFolder()
        var (vault, _, _) = makeVault()
        let clock = TestClock()
        vault.throttle.now = { clock.now }
        let state = try await lockedOnState(vault, folder)

        for attempt in 1...5 {
            do {
                try await state.changeAppLockPassword(current: "wrong-password", new: newPassword)
                XCTFail("Wrong password accepted")
            } catch {
                let expected: AppLockVault.VaultError = attempt < 5 ? .wrongPassword : .tooManyAttempts(seconds: 30)
                XCTAssertEqual(error as? AppLockVault.VaultError, expected, "attempt \(attempt)")
            }
        }
        XCTAssertEqual(vault.throttle.failedAttempts, 5, "Same count as the lock screen")
        // While the wait runs even the right password is not checked, in either sheet
        let checks: [@MainActor () async throws -> Void] = [
            { _ = try await state.changeAppLockPassword(current: self.password, new: self.newPassword) },
            { try await state.disableAppLock(password: self.password) },
        ]
        for check in checks {
            do {
                try await check()
                XCTFail("Checked during the lockout")
            } catch {
                XCTAssertEqual(error as? AppLockVault.VaultError, .tooManyAttempts(seconds: 30))
            }
        }
        XCTAssertTrue(vault.isLockEnabled, "Nothing changed")

        clock.advance(31)
        try await state.disableAppLock(password: password)
        XCTAssertFalse(state.isAppLockEnabled)
        XCTAssertEqual(vault.throttle.failedAttempts, 0, "The right password resets the count")
        state.shutdown()
    }

    func testThrottleKeepsTheLockScreenScheduleAndFormat() {
        let store = MemorySecretStore()
        let clock = TestClock()
        var throttle = UnlockThrottle(store: store)
        throttle.now = { clock.now }
        XCTAssertEqual((1...10).map(UnlockThrottle.lockoutDuration), [0, 0, 0, 0, 30, 60, 300, 900, 1800, 1800])
        for _ in 1...4 { XCTAssertEqual(try throttle.recordFailure().lockout, 0) }
        XCTAssertNil(throttle.remainingLockout)
        XCTAssertEqual(try throttle.recordFailure().lockout, 30)
        XCTAssertEqual(throttle.remainingLockout, 30)
        XCTAssertThrowsError(try throttle.checkAllowed())
        // Stored as text, like earlier versions (existing counts carry over)
        XCTAssertEqual(store.read(UnlockThrottle.attemptsAccount), Data("5".utf8))
        clock.advance(30)
        XCTAssertNil(throttle.remainingLockout)
        XCTAssertNoThrow(try throttle.checkAllowed())
        XCTAssertEqual(UnlockThrottle.waitMessage(seconds: 30), "Too many attempts. Try again in 30 seconds.")
        XCTAssertEqual(UnlockThrottle.waitMessage(seconds: 300), "Too many attempts. Try again in 5 minutes.")
        throttle.reset()
        XCTAssertEqual(throttle.failedAttempts, 0)
        XCTAssertEqual(store.accounts, [])
    }
}
