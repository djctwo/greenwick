import XCTest
@testable import Greenwick

/// Settings > Back Up Journal / Restore Backup, as the app drives them (without the file
/// panels). Bug fixed here: restoring a password-protected backup always failed, because
/// the app never asked for the password.
final class BackupFlowTests: XCTestCase {
    private let password = "backup-pass-1"

    @MainActor
    private func makeState(_ folder: URL) -> AppState {
        let (vault, _, _) = makeVault()
        return AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                        screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true))
    }

    @MainActor
    private func addMyTrade(_ state: AppState) throws {
        var mine = sampleTrades()[0]
        mine.ticket = 42
        mine.symbol = "MINE"
        mine.isSample = false
        XCTAssertEqual(try state.tradeRepository.bulkInsert([mine]), 1)
    }

    @MainActor
    func testRestoringAProtectedBackupAsksForItsPassword() async throws {
        let state = makeState(try makeScratchFolder())
        defer { state.shutdown() }
        try addMyTrade(state)
        let model = BackupFlowModel(appState: state)
        var restoredCount = 0
        model.onRestored = { restoredCount += 1 }
        let sealed = try BackupEncryption.encrypt(try backupBytes(with: sampleTrades()), password: password)

        await model.receiveRestoreFile(sealed)
        XCTAssertEqual(model.sheet, .restorePassword, "A protected backup must ask for its password")
        XCTAssertEqual(try state.tradeRepository.fetchAll().map(\.symbol), ["MINE"], "Nothing restored yet")

        model.password = "not-the-password"
        await model.submitRestorePassword()
        XCTAssertEqual(model.sheet, .restorePassword, "Stays open to try again")
        XCTAssertTrue(model.error?.contains("Wrong password") == true, model.error ?? "no message")
        XCTAssertEqual(model.password, "", "The wrong password is cleared")
        XCTAssertEqual(try state.tradeRepository.fetchAll().map(\.symbol), ["MINE"], "Journal untouched")
        XCTAssertEqual(restoredCount, 0)

        model.password = password
        await model.submitRestorePassword()
        XCTAssertNil(model.sheet)
        XCTAssertNil(model.error)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertEqual(restoredCount, 1)
    }

    @MainActor
    func testPlainBackupRestoresWithoutAskingForAPassword() async throws {
        let state = makeState(try makeScratchFolder())
        defer { state.shutdown() }
        try addMyTrade(state)
        let model = BackupFlowModel(appState: state)
        await model.receiveRestoreFile(try backupBytes(with: sampleTrades()))
        XCTAssertNil(model.sheet)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
    }

    @MainActor
    func testPasswordProtectionIsOnByDefaultOnlyWithAppLock() async throws {
        let state = makeState(try makeScratchFolder())
        defer { state.shutdown() }
        let model = BackupFlowModel(appState: state)
        model.beginExport()
        XCTAssertEqual(model.sheet, .export)
        XCTAssertFalse(model.protectWithPassword, "Off when App Lock is off")
        model.close()

        _ = try await state.enableAppLock(password: "correct-horse-42")
        model.beginExport()
        XCTAssertTrue(model.protectWithPassword, "On when App Lock is on")
    }

    @MainActor
    func testBackupPasswordIsCheckedLikeTheAppLockPassword() throws {
        let state = makeState(try makeScratchFolder())
        defer { state.shutdown() }
        let model = BackupFlowModel(appState: state)
        model.beginExport()
        XCTAssertNil(try model.exportPassword(), "No protection, no password")

        model.protectWithPassword = true
        XCTAssertThrowsError(try model.exportPassword()) {
            XCTAssertEqual($0 as? BackupFlowModel.InputError, .empty)
        }
        model.password = password
        model.confirmation = password + "x"
        XCTAssertThrowsError(try model.exportPassword()) {
            XCTAssertEqual($0 as? BackupFlowModel.InputError, .mismatch)
        }
        model.password = "short"
        model.confirmation = "short"
        XCTAssertThrowsError(try model.exportPassword()) {
            XCTAssertEqual($0 as? AppLockVault.VaultError, .passwordTooShort)
        }
        model.password = password
        model.confirmation = password
        XCTAssertEqual(try model.exportPassword(), password)
    }

    /// End to end without the panels: back up with a password, restore it into another journal
    @MainActor
    func testProtectedBackupMadeByTheAppRestoresWithItsPassword() async throws {
        let folder = try makeScratchFolder()
        let source = makeState(folder.appendingPathComponent("a", isDirectory: true))
        defer { source.shutdown() }
        XCTAssertEqual(try source.tradeRepository.bulkInsert(sampleTrades()), 30)
        let file = folder.appendingPathComponent("Greenwick_Backup.sjbackup-enc")
        try await BackupFlowModel(appState: source).writeExport(to: file, password: password)
        let written = try Data(contentsOf: file)
        XCTAssertEqual(BackupEncryption.format(of: written), .protected)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)

        let target = makeState(folder.appendingPathComponent("b", isDirectory: true))
        defer { target.shutdown() }
        let model = BackupFlowModel(appState: target)
        await model.receiveRestoreFile(written)
        model.password = password
        await model.submitRestorePassword()
        XCTAssertEqual(try target.tradeRepository.count(), 30)
    }

    /// The app locked while a file panel was open (idle or background lock): the journal is
    /// closed, so nothing may be backed up from or restored into the empty stand-in
    @MainActor
    func testNothingIsBackedUpOrRestoredAfterTheAppLocked() async throws {
        let folder = try makeScratchFolder()
        let state = makeState(folder.appendingPathComponent("j", isDirectory: true))
        defer { state.shutdown() }
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: "correct-horse-42")
        state.lock()
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }

        let model = BackupFlowModel(appState: state)
        var restored = false
        model.onRestored = { restored = true }
        let file = folder.appendingPathComponent("late.sjbackup")
        do {
            try await model.writeExport(to: file, password: nil)
            XCTFail("No backup of the closed journal")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        await model.receiveRestoreFile(try backupBytes(with: sampleTrades()))
        XCTAssertFalse(restored)
        XCTAssertNil(model.sheet)

        let unlocked = await state.unlock(password: "correct-horse-42")
        XCTAssertEqual(unlocked, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30, "The journal is as it was")
    }
}
