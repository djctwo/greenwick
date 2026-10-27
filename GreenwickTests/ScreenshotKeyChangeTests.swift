import CryptoKit
import XCTest
@testable import Greenwick

/// Screenshots through the app's lifecycle: sealed at launch / unlock when an older version
/// left them plain, unreadable while locked, re-sealed by every key change (whose old key
/// stays until every screenshot opens with the new one), erased with everything else, and
/// not part of backups.
@MainActor
final class ScreenshotKeyChangeTests: XCTestCase {
    private let password = "correct-horse-42"
    private let newPassword = "another-pass-1"
    private let image = ScreenshotStorageTests.jpegLike

    private func makeState(_ vault: AppLockVault, _ folder: URL,
                           screenshotWriter: JournalFileWriter = .secure) -> AppState {
        AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true),
                 screenshotWriter: screenshotWriter)
    }

    private func shots(_ folder: URL) -> URL { folder.appendingPathComponent("Screenshots", isDirectory: true) }

    /// Every app-named screenshot file under the folder
    private func screenshotFiles(_ folder: URL) -> [URL] {
        ScreenshotManager(baseDir: shots(folder)).list().files
    }

    private func opens(_ file: URL, with key: SymmetricKey) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        return (try? ScreenshotFormat.open(data, key: key, name: file.lastPathComponent)) == image
    }

    /// A lock-off journal with three sealed screenshots on two trades
    private func stateWithScreenshots(_ vault: AppLockVault, _ folder: URL,
                                      screenshotWriter: JournalFileWriter = .secure) throws -> AppState {
        let state = makeState(vault, folder, screenshotWriter: screenshotWriter)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        for trade in [1, 1, 2] as [Int64] { _ = try state.screenshots.saveImageData(image, for: trade) }
        XCTAssertEqual(screenshotFiles(folder).count, 3)
        return state
    }

    // MARK: - Older versions' plain files

    func testLaunchEncryptsPlainScreenshotsFromAnOlderVersion() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        makeState(vault, folder).shutdown()
        let plain = try ScreenshotStorageTests.plantPlainFile(in: shots(folder), trade: 5)

        let state = makeState(vault, folder)
        defer { state.shutdown() }
        let sealedCount = await state.legacyScreenshotSealing?.value
        XCTAssertEqual(sealedCount, 1)
        ScreenshotStorageTests.assertNotAnImage(try Data(contentsOf: plain))
        XCTAssertTrue(opens(plain, with: try XCTUnwrap(state.database.encryptionKey)))
    }

    func testWithAppLockPlainScreenshotsAreEncryptedAtUnlockNotBefore() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let first = makeState(vault, folder)
        _ = try await first.enableAppLock(password: password)
        first.shutdown()
        let plain = try ScreenshotStorageTests.plantPlainFile(in: shots(folder), trade: 5)

        let state = makeState(vault, folder)
        defer { state.shutdown() }
        XCTAssertTrue(state.isLocked)
        XCTAssertNil(state.legacyScreenshotSealing)
        XCTAssertNil(state.screenshots.loadImageData(filename: plain.lastPathComponent, for: 5))
        XCTAssertEqual(try Data(contentsOf: plain), image, "Nothing is written while locked")

        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        let sealedCount = await state.legacyScreenshotSealing?.value
        XCTAssertEqual(sealedCount, 1)
        XCTAssertTrue(opens(plain, with: try XCTUnwrap(state.database.encryptionKey)))
    }

    // MARK: - Locked

    func testLockedGreenwickDecryptsAndWritesNoScreenshot() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try stateWithScreenshots(vault, folder)
        defer { state.shutdown() }
        _ = try await state.enableAppLock(password: password)
        let file = try XCTUnwrap(screenshotFiles(folder).first)
        let trade = Int64(file.deletingLastPathComponent().lastPathComponent) ?? 0
        XCTAssertEqual(state.screenshots.loadImageData(filename: file.lastPathComponent, for: trade), image)

        state.lock()
        XCTAssertNil(state.screenshots.loadImageData(filename: file.lastPathComponent, for: trade),
                     "Decrypted while the lock screen shows")
        XCTAssertThrowsError(try state.screenshots.saveImageData(image, for: trade))
        for _ in 0..<50 where state.database.isPersistent { await Task.yield() }
        XCTAssertNil(state.screenshots.loadImageData(filename: file.lastPathComponent, for: trade))
        XCTAssertEqual(screenshotFiles(folder).count, 3)

        let unlocked = await state.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(state.screenshots.loadImageData(filename: file.lastPathComponent, for: trade), image)
    }

    // MARK: - Key rotation

    func testTurningAppLockOnResealsEveryScreenshot() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let state = try stateWithScreenshots(vault, folder)
        defer { state.shutdown() }
        let plain = try ScreenshotStorageTests.plantPlainFile(in: shots(folder), trade: 3)
        let oldKey = try XCTUnwrap(state.database.encryptionKey)

        let change = try await state.enableAppLock(password: password)
        XCTAssertEqual(change, .done(hasRecovery: true))
        let newKey = try XCTUnwrap(state.database.encryptionKey)
        XCTAssertEqual(screenshotFiles(folder).count, 4)
        for file in screenshotFiles(folder) {
            XCTAssertTrue(opens(file, with: newKey), "Not re-sealed: \(file.lastPathComponent)")
            XCTAssertFalse(opens(file, with: oldKey), "The old (lock-off) key still opens a screenshot")
        }
        XCTAssertTrue(opens(plain, with: newKey))
        XCTAssertNil(store.read(AppLockVault.Account.plainKey), "Old key deleted once everything moved")
        _ = try state.screenshots.saveImageData(image, for: 9)
        XCTAssertTrue(screenshotFiles(folder).allSatisfy { opens($0, with: newKey) }, "New saves use the new key")
    }

    func testChangingThePasswordResealsEveryScreenshot() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let state = try stateWithScreenshots(vault, folder)
        defer { state.shutdown() }
        _ = try await state.enableAppLock(password: password)
        let oldKey = try XCTUnwrap(state.database.encryptionKey)

        let change = try await state.changeAppLockPassword(current: password, new: newPassword)
        XCTAssertEqual(change, .done(hasRecovery: true))
        let newKey = try XCTUnwrap(state.database.encryptionKey)
        for file in screenshotFiles(folder) {
            XCTAssertTrue(opens(file, with: newKey))
            XCTAssertFalse(opens(file, with: oldKey))
        }
        XCTAssertNil(store.read(AppLockVault.Account.previousKey))
    }

    /// A screenshot that can't be re-written keeps the old key stored (the rotation stays
    /// pending); nothing may drop that key meanwhile; the next unlock finishes the job
    func testAScreenshotThatCannotBeResealedKeepsTheRotationPending() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let disk = FlakyDisk()
        let state = try stateWithScreenshots(vault, folder, screenshotWriter: disk.writer)
        let oldKey = try XCTUnwrap(state.database.encryptionKey)
        disk.isFull = true

        let change = try await state.enableAppLock(password: password)
        XCTAssertEqual(change, .finishesAtNextUnlock)
        let newKey = try XCTUnwrap(state.database.encryptionKey)
        XCTAssertEqual(store.read(AppLockVault.Account.plainKey).flatMap { Data(base64Encoded: $0) },
                       AppLockVault.raw(oldKey), "The old key must stay while a screenshot needs it")
        XCTAssertTrue(screenshotFiles(folder).allSatisfy { opens($0, with: oldKey) })

        // Neither another password change nor Turn Off may drop that key now
        do {
            _ = try await state.changeAppLockPassword(current: password, new: newPassword)
            XCTFail("A second change would have replaced the key the screenshots need")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .screenshotsPending)
        }
        XCTAssertNoThrow(try vault.verify(password: password), "Nothing changed")
        do {
            try await state.disableAppLock(password: password)
            XCTFail("Turning off would have dropped the key the screenshots need")
        } catch {
            XCTAssertEqual(error as? AppLockVault.VaultError, .screenshotsPending)
        }
        XCTAssertTrue(state.isAppLockEnabled)
        XCTAssertNotNil(store.read(AppLockVault.Account.plainKey))
        state.shutdown()

        // The disk works again: the next unlock re-seals them and only then drops the old key
        let relaunched = makeState(vault, folder)
        defer { relaunched.shutdown() }
        let unlocked = await relaunched.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(AppLockVault.raw(try XCTUnwrap(relaunched.database.encryptionKey)), AppLockVault.raw(newKey))
        for file in screenshotFiles(folder) {
            XCTAssertTrue(opens(file, with: newKey))
            XCTAssertFalse(opens(file, with: oldKey))
        }
        XCTAssertNil(store.read(AppLockVault.Account.plainKey), "Done: the old key goes")
    }

    /// The same at an unlock: while a screenshot still can't be re-written, the unlock
    /// opens the journal but keeps the old key
    func testUnlockKeepsTheOldKeyWhileAScreenshotCannotBeResealed() async throws {
        let folder = try makeScratchFolder()
        let (vault, store, _) = makeVault()
        let disk = FlakyDisk()
        let state = try stateWithScreenshots(vault, folder, screenshotWriter: disk.writer)
        disk.isFull = true
        let change = try await state.enableAppLock(password: password)
        XCTAssertEqual(change, .finishesAtNextUnlock)
        state.shutdown()

        let relaunched = makeState(vault, folder, screenshotWriter: disk.writer)
        defer { relaunched.shutdown() }
        let unlocked = await relaunched.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertNotNil(store.read(AppLockVault.Account.plainKey), "Still needed by the screenshots")
        XCTAssertEqual(relaunched.pendingScreenshotKeys.count, 1)
    }

    // MARK: - Erase and backups

    func testEraseAllLocalDataRemovesEveryScreenshot() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = try stateWithScreenshots(vault, folder)
        defer { state.shutdown() }
        _ = try ScreenshotStorageTests.plantPlainFile(in: shots(folder), trade: 4)
        let leftover = shots(folder).appendingPathComponent("1/\(UUID().uuidString).jpg.saving-\(UUID().uuidString)")
        try Data([1]).write(to: leftover)
        _ = try await state.enableAppLock(password: password)
        state.lock()
        for _ in 0..<50 where state.database.isPersistent { await Task.yield() }

        try await state.eraseAllLocalData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: shots(folder).path))
        try assertOnlyTheJournal(in: folder)
    }

    /// Backups hold the journal only: a screenshot's name is in its trade, never its image
    /// (sealed or not). Restoring writes no screenshot file.
    func testBackupsDoNotContainScreenshotImages() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        defer { state.shutdown() }
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        let trade = try XCTUnwrap(try state.tradeRepository.fetchAll().first?.id)
        let name = try state.screenshots.saveImageData(image, for: trade)
        try state.tradeRepository.updateScreenshots(tradeId: trade, screenshots: name)
        let sealed = try Data(contentsOf: try XCTUnwrap(state.screenshots.imageURL(filename: name, for: trade)))

        let backup = try state.database.serializedSnapshot()
        XCTAssertNotNil(backup.range(of: Data(name.utf8)), "The trade keeps the screenshot's name")
        XCTAssertNil(backup.range(of: ScreenshotStorageTests.marker), "No image bytes in a backup")
        XCTAssertNil(backup.range(of: sealed.suffix(32)), "No sealed screenshot in a backup")

        try BackupService.restore(from: backup, password: nil, into: state.database)
        XCTAssertEqual(screenshotFiles(folder).count, 1, "Restore writes no screenshot file")
    }
}
