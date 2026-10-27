import CryptoKit
import XCTest
@testable import Greenwick

/// F1 / F5: App Lock must protect the data, not just the screen. With the lock on, the
/// journal key exists only wrapped by the password (plus the Touch ID / Mac password
/// recovery copy), and nothing is decrypted before unlock.
final class AppLockVaultTests: XCTestCase {
    private let password = "correct-horse-42"

    /// Turn the lock on the way the app does: rotate to a new key (journal re-seal omitted)
    @discardableResult
    private func enable(_ vault: AppLockVault, from current: SymmetricKey, password: String? = nil,
                        hasRecovery: Bool = true) throws -> SymmetricKey {
        let newKey = SymmetricKey(size: .bits256)
        try vault.beginRotation(to: newKey, password: password ?? self.password, current: current)
        XCTAssertEqual(vault.commitRotation(to: newKey), hasRecovery)
        return newKey
    }

    func testPasswordKeyDerivationUsesAHighIterationCount() {
        XCTAssertGreaterThanOrEqual(AppLockVault.defaultIterations, 600_000)
        XCTAssertGreaterThanOrEqual(AppLockVault.live.iterations, 600_000)
    }

    func testEnablingStoresOnlyANewWrappedKey() async throws {
        let (vault, store, presence) = makeVault()
        let old = try vault.plainKey(createIfMissing: true)
        let new = try enable(vault, from: old)

        XCTAssertTrue(vault.isLockEnabled)
        XCTAssertEqual(store.accounts, [AppLockVault.Account.wrappedKey, AppLockVault.Account.recoveryFingerprint])
        let blob = try XCTUnwrap(store.read(AppLockVault.Account.wrappedKey))
        for key in [old, new] {
            XCTAssertNil(blob.range(of: AppLockVault.raw(key)), "The wrapped item must not contain a key")
        }
        let unwrapped = try vault.unlockKeys(password: password, mayCreateKey: false)
        XCTAssertEqual(unwrapped.primary, AppLockVault.raw(new), "Rotated: the old key is gone")
        XCTAssertEqual(unwrapped.fallbacks, [])
        XCTAssertTrue(presence.hasSecret(), "Recovery copy for Touch ID / Mac password")
        let recoveryCopy = await presence.retrieve(reason: "t")
        XCTAssertEqual(recoveryCopy, AppLockVault.raw(new))
        XCTAssertThrowsError(try vault.plainKey(createIfMissing: true), "No new plain key while locked")
    }

    func testOnlyTheRightPasswordUnwrapsTheKey() throws {
        let (vault, _, _) = makeVault()
        let key = try enable(vault, from: try vault.plainKey(createIfMissing: true))
        XCTAssertThrowsError(try vault.unlockKeys(password: "wrong-password", mayCreateKey: false)) {
            XCTAssertEqual($0 as? AppLockVault.VaultError, .wrongPassword)
        }
        XCTAssertEqual(try vault.unlockKeys(password: password, mayCreateKey: false).primary, AppLockVault.raw(key))
    }

    func testOlderInstallIsRecognisedAndNeedsRotation() throws {
        let (vault, store, _) = makeVault()
        let key = try vault.plainKey(createIfMissing: true)
        store.write(Data(PasswordHasher.hash(password).utf8), account: AppLockVault.Account.legacyHash)
        XCTAssertTrue(vault.isLockEnabled)
        XCTAssertThrowsError(try vault.unlockKeys(password: "nope-nope", mayCreateKey: false))
        let keys = try vault.unlockKeys(password: password, mayCreateKey: false)
        XCTAssertNil(keys.primary)
        XCTAssertEqual(keys.fallbacks, [AppLockVault.raw(key)])
        XCTAssertTrue(keys.needsRotation)
    }

    /// A password change rotates the key; until the journal is re-sealed (step 2) the old
    /// key stays available as a fallback, wrapped with the new password
    func testChangingThePasswordRotatesWithAFallbackUntilCommitted() throws {
        let (vault, store, _) = makeVault()
        let first = try enable(vault, from: try vault.plainKey(createIfMissing: true))
        let second = SymmetricKey(size: .bits256)
        try vault.beginRotation(to: second, password: "another-pass-1", current: first)

        XCTAssertThrowsError(try vault.unlockKeys(password: password, mayCreateKey: false))
        let pending = try vault.unlockKeys(password: "another-pass-1", mayCreateKey: false)
        XCTAssertEqual(pending.primary, AppLockVault.raw(second))
        XCTAssertEqual(pending.fallbacks, [AppLockVault.raw(first)], "Interrupted here: old key still reachable")

        _ = vault.commitRotation(to: second)
        XCTAssertEqual(store.accounts, [AppLockVault.Account.wrappedKey, AppLockVault.Account.recoveryFingerprint])
        XCTAssertEqual(try vault.unlockKeys(password: "another-pass-1", mayCreateKey: false).fallbacks, [])
        XCTAssertThrowsError(try vault.beginRotation(to: first, password: "short", current: second)) {
            XCTAssertEqual($0 as? AppLockVault.VaultError, .passwordTooShort)
        }
    }

    func testTurningTheLockOffNeedsThePasswordAndUnwrapsBack() throws {
        let (vault, store, presence) = makeVault()
        let key = try enable(vault, from: try vault.plainKey(createIfMissing: true))
        XCTAssertThrowsError(try vault.disableLock(password: "wrong-password", key: key))
        XCTAssertTrue(vault.isLockEnabled)

        try vault.disableLock(password: password, key: key)
        XCTAssertFalse(vault.isLockEnabled)
        XCTAssertFalse(presence.hasSecret())
        XCTAssertEqual(store.accounts, [AppLockVault.Account.plainKey])
        XCTAssertEqual(AppLockVault.raw(try vault.plainKey(createIfMissing: false)), AppLockVault.raw(key))
    }

    func testForgotPasswordRecoversThroughTheDeviceOwnerOnly() async throws {
        let (vault, _, presence) = makeVault()
        let key = try enable(vault, from: try vault.plainKey(createIfMissing: true))

        presence.ownerConfirms = false
        do {
            _ = try await vault.recoveryKey(reason: "test")
            XCTFail("Cancelled Touch ID / Mac password must not unlock")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .ownerNotConfirmed)
        }
        XCTAssertTrue(vault.isLockEnabled)

        presence.ownerConfirms = true
        let recovered = try await vault.recoveryKey(reason: "test")
        XCTAssertEqual(AppLockVault.raw(recovered), AppLockVault.raw(key))
        XCTAssertTrue(vault.isLockEnabled, "Nothing changes until the key has opened the journal")
        try vault.removeLock(keeping: recovered)
        XCTAssertFalse(vault.isLockEnabled)
        XCTAssertEqual(presence.prompts, 2)
    }

    /// Ad-hoc signed builds can't create `.userPresence` items: enabling still works, the
    /// app says recovery isn't available, and Forgot Password can't bypass the lock.
    func testWithoutPresenceSupportThereIsNoBypass() async throws {
        let (vault, _, _) = makeVault(presenceSupported: false)
        try enable(vault, from: try vault.plainKey(createIfMissing: true), hasRecovery: false)
        XCTAssertFalse(vault.isRecoveryAvailable)
        do {
            _ = try await vault.recoveryKey(reason: "test")
            XCTFail("No recovery copy, so no recovery")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .recoveryUnavailable)
        }
        XCTAssertTrue(vault.isLockEnabled)
    }

    func testWrappedKeyUsesFreshSaltEachTime() throws {
        let (vault, _, _) = makeVault()
        let key = SymmetricKey(size: .bits256)
        let first = try JSONDecoder().decode(AppLockVault.WrappedKey.self, from: try vault.wrap(key, password: password))
        let second = try JSONDecoder().decode(AppLockVault.WrappedKey.self, from: try vault.wrap(key, password: password))
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertEqual(first.salt.count, 16)
        XCTAssertEqual(first.iterations, vault.iterations)
    }
}

/// The app's startup and lock lifecycle around the vault
final class AppLockLifecycleTests: XCTestCase {
    private let password = "correct-horse-42"

    @MainActor
    private func makeState(_ vault: AppLockVault, _ folder: URL) -> AppState {
        AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true))
    }

    @MainActor
    func testLockedLaunchDecryptsNothingBeforeThePassword() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let first = makeState(vault, folder)
        XCTAssertFalse(first.isLocked)
        XCTAssertEqual(try first.tradeRepository.bulkInsert(sampleTrades()), 30)
        _ = try await first.enableAppLock(password: password)
        first.shutdown()

        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let onDisk = try Data(contentsOf: URL(fileURLWithPath: path))
        let state = makeState(vault, folder)
        XCTAssertTrue(state.isLocked)
        XCTAssertFalse(state.database.isPersistent, "The journal stays closed while locked")
        XCTAssertEqual(try state.tradeRepository.count(), 0)
        XCTAssertNil(store.read(AppLockVault.Account.plainKey), "No usable key without the password")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), onDisk, "Nothing decrypted to disk")
        try assertOnlyTheJournal(in: folder)

        let wrong = await state.unlock(password: "wrong-password")
        XCTAssertEqual(wrong, .wrongPassword)
        XCTAssertTrue(state.isLocked)

        let right = await state.unlock(password: password)
        XCTAssertEqual(right, .unlocked)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertFalse(DatabaseEncryption.fileIsPlaintext(at: path))
        state.shutdown()
    }

    @MainActor
    func testAutoLockClosesTheJournalAndForgetsTheKey() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)

        state.lock()
        XCTAssertTrue(state.isLocked)
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }
        XCTAssertFalse(state.database.isPersistent)
        XCTAssertNil(state.database.encryptionKey)
        XCTAssertEqual(try state.tradeRepository.count(), 0)

        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    /// An install from before key wrapping (password hash + bare key) whose journal was left
    /// in plaintext: encrypted at launch, before the lock screen; wrapped at unlock.
    @MainActor
    func testOlderLockedInstallIsSecuredAtLaunchAndMigratedAtUnlock() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        _ = try vault.plainKey(createIfMissing: true)
        store.write(Data(PasswordHasher.hash(password).utf8), account: AppLockVault.Account.legacyHash)
        try backupBytes(with: sampleTrades()).write(to: URL(fileURLWithPath: path))
        XCTAssertTrue(DatabaseEncryption.fileIsPlaintext(at: path))

        let state = makeState(vault, folder)
        XCTAssertTrue(state.isLocked)
        XCTAssertFalse(DatabaseEncryption.fileIsPlaintext(at: path), "Encrypted before anything else")

        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertEqual(store.accounts, [AppLockVault.Account.wrappedKey, AppLockVault.Account.recoveryFingerprint])
        state.shutdown()
    }

    @MainActor
    func testDisablingTheLockKeepsTheJournal() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)
        do {
            try await state.disableAppLock(password: "wrong-password")
            XCTFail("Turning the lock off needs the password")
        } catch {}
        XCTAssertTrue(state.isAppLockEnabled)
        try await state.disableAppLock(password: password)
        XCTAssertFalse(state.isAppLockEnabled)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        XCTAssertFalse(relaunched.isLocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    @MainActor
    func testForgotPasswordWithRecoveryKeepsTheJournal() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let first = makeState(vault, folder)
        _ = try first.tradeRepository.bulkInsert(sampleTrades())
        _ = try await first.enableAppLock(password: password)
        first.shutdown()

        let state = makeState(vault, folder)
        XCTAssertTrue(state.isRecoveryAvailable)
        try await state.recoverWithDeviceOwner()
        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.isAppLockEnabled)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    @MainActor
    func testEraseAllLocalDataLeavesNothingBehind() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, presence) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)
        let screenshots = folder.appendingPathComponent("Screenshots/1", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        try Data([1]).write(to: screenshots.appendingPathComponent("\(UUID().uuidString).jpg"))
        try Data([2]).write(to: folder.appendingPathComponent("Greenwick.sqlite.unreadable-2026"))
        try Data([3]).write(to: folder.appendingPathComponent("Greenwick.sqlite-wal"))
        state.lock()
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }

        try await state.eraseAllLocalData()
        XCTAssertFalse(state.isLocked)
        XCTAssertFalse(state.isAppLockEnabled)
        XCTAssertFalse(presence.hasSecret())
        XCTAssertEqual(store.accounts, [AppLockVault.Account.plainKey], "Only the new journal's key")
        XCTAssertEqual(try state.tradeRepository.count(), 0)
        try assertOnlyTheJournal(in: folder)
        state.shutdown()
    }

    /// "Erase All Local Data" on the lock screen is permanent: without the Mac owner's
    /// confirmation (Touch ID or login password) nothing may be erased
    @MainActor
    func testEraseAllLocalDataNeedsTheMacOwner() async throws {
        let folder = try makeScratchFolder()
        let owner = MemoryOwnerCheck(confirms: false)
        let (vault, store, presence) = makeVault(presenceSupported: false, owner: owner)
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)
        state.lock()
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let sealed = try Data(contentsOf: URL(fileURLWithPath: path))

        do {
            try await state.eraseAllLocalData()
            XCTFail("Erasing needs the Mac owner's confirmation")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .eraseNotConfirmed)
        }
        XCTAssertEqual(owner.prompts, 1)
        XCTAssertTrue(state.isLocked)
        XCTAssertTrue(state.isAppLockEnabled)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), sealed, "Journal untouched")
        XCTAssertTrue(store.accounts.contains(AppLockVault.Account.wrappedKey))
        XCTAssertFalse(presence.hasSecret())

        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        state.shutdown()
    }

    // MARK: Key rotation (turning the lock on, changing the password)

    private func journalOpens(_ folder: URL, with key: SymmetricKey) -> Bool {
        guard let sealed = try? Data(contentsOf: folder.appendingPathComponent("Greenwick.sqlite")) else { return false }
        return (try? JournalFormat.open(sealed, key: key)) != nil
    }

    @MainActor
    func testTurningTheLockOnRotatesTheKey() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, presence) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        let old = try XCTUnwrap(state.database.encryptionKey)
        XCTAssertTrue(journalOpens(folder, with: old))

        _ = try await state.enableAppLock(password: password)
        let new = try XCTUnwrap(state.database.encryptionKey)
        XCTAssertNotEqual(AppLockVault.raw(new), AppLockVault.raw(old))
        XCTAssertFalse(journalOpens(folder, with: old), "A leaked old key must not open the journal")
        XCTAssertTrue(journalOpens(folder, with: new))
        let recoveryCopy = await presence.retrieve(reason: "t")
        XCTAssertEqual(recoveryCopy, AppLockVault.raw(new))

        // Later saves use the new key too
        _ = try state.tradeRepository.bulkInsert([{ var t = sampleTrades()[0]; t.ticket = 77; return t }()])
        XCTAssertTrue(journalOpens(folder, with: new))
        state.shutdown()
    }

    @MainActor
    func testChangingThePasswordRotatesTheKey() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)
        let before = try XCTUnwrap(state.database.encryptionKey)
        do {
            try await state.changeAppLockPassword(current: "wrong-password", new: "another-pass-1")
            XCTFail("The current password is required")
        } catch {}
        XCTAssertTrue(journalOpens(folder, with: before))

        try await state.changeAppLockPassword(current: password, new: "another-pass-1")
        let after = try XCTUnwrap(state.database.encryptionKey)
        XCTAssertNotEqual(AppLockVault.raw(after), AppLockVault.raw(before))
        XCTAssertFalse(journalOpens(folder, with: before))
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let old = await relaunched.unlock(password: password)
        XCTAssertEqual(old, .wrongPassword)
        let new = await relaunched.unlock(password: "another-pass-1")
        XCTAssertEqual(new, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// The app stops between the steps of a key rotation (after step 1, or after step 2):
    /// the journal must still open with the password, and the next unlock finishes the job.
    @MainActor
    func testInterruptedRotationLeavesTheJournalDecryptable() async throws {
        for alreadyLocked in [false, true] {
            for resealed in [false, true] {
                let folder = try makeScratchFolder()
                let (vault, store, _) = makeVault()
                let state = makeState(vault, folder)
                _ = try state.tradeRepository.bulkInsert(sampleTrades())
                var unlockWith = password
                if alreadyLocked {
                    _ = try await state.enableAppLock(password: password)
                    unlockWith = "another-pass-1" // interrupted password change
                }
                let current = try XCTUnwrap(state.database.encryptionKey)
                let newKey = SymmetricKey(size: .bits256)
                try vault.beginRotation(to: newKey, password: unlockWith, current: current)   // step 1
                if resealed { try state.database.rekey(to: newKey) }                           // step 2
                state.shutdown()                                                              // stop: no step 3

                let relaunched = makeState(vault, folder)
                XCTAssertTrue(relaunched.isLocked)
                let result = await relaunched.unlock(password: unlockWith)
                XCTAssertEqual(result, .unlocked, "locked: \(alreadyLocked), resealed: \(resealed)")
                XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
                // Finished: only the new wrapped key remains and it opens the file
                XCTAssertEqual(store.accounts, [AppLockVault.Account.wrappedKey, AppLockVault.Account.recoveryFingerprint])
                XCTAssertTrue(journalOpens(folder, with: newKey))
                XCTAssertFalse(journalOpens(folder, with: current))
                relaunched.shutdown()
            }
        }
    }
}
