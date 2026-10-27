import CryptoKit
import XCTest
@testable import Greenwick

/// Final review: a disk problem while opening never sets a healthy journal aside; one running
/// copy per data folder; a restore can't land after the final save (Dojix #5).
@MainActor
final class JournalDurabilityTests: XCTestCase {
    private let password = "correct-horse-42"

    private func makeState(_ vault: AppLockVault, _ folder: URL, writer: JournalFileWriter = .secure) -> AppState {
        AppState(vault: vault, databasePath: journal(folder).path,
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true),
                 journalWriter: writer)
    }

    private func journal(_ folder: URL) -> URL { folder.appendingPathComponent("Greenwick.sqlite") }

    private func setAside(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains(".unreadable-") }
    }

    /// A journal with the 30 sample trades, saved and closed (lock on or off)
    private func savedJournal(_ vault: AppLockVault, _ folder: URL, lockOn: Bool) async throws -> Data {
        let state = makeState(vault, folder)
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        if lockOn { _ = try await state.enableAppLock(password: password) }
        state.shutdown()
        return try Data(contentsOf: journal(folder))
    }

    // MARK: - Finding 2: a full disk while opening

    /// Lock off. Opening rewrites the file once; on a full disk that write fails. Before the
    /// fix the healthy journal was renamed to `.unreadable-…` and the next launch started an
    /// empty one without a word. Now it opens in memory, says saving failed, and the file
    /// stays exactly where it is.
    func testFullDiskWhileOpeningKeepsTheJournalInPlace() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let onDisk = try await savedJournal(vault, folder, lockOn: false)
        let disk = FlakyDisk()
        disk.isFull = true

        let state = makeState(vault, folder, writer: disk.writer)
        XCTAssertGreaterThan(disk.failedWrites, 0, "Setup: the open-time save hit the full disk")
        XCTAssertFalse(state.isDatabaseFailed)
        XCTAssertEqual(try state.tradeRepository.count(), 30, "Open in memory")
        XCTAssertTrue(try XCTUnwrap(state.databaseError).contains("couldn't save your journal"))
        XCTAssertEqual(try setAside(folder), [], "Nothing set aside")
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)
        state.shutdown()
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk, "Quitting on a full disk loses nothing")

        let relaunched = makeState(vault, folder)
        XCTAssertNil(relaunched.olderJournal)
        XCTAssertNil(relaunched.databaseError)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Lock on: the same through unlock, which used to treat any open error like a wrong key
    func testFullDiskWhileUnlockingKeepsTheJournalInPlace() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let onDisk = try await savedJournal(vault, folder, lockOn: true)
        let disk = FlakyDisk()
        disk.isFull = true

        let state = makeState(vault, folder, writer: disk.writer)
        let result = await state.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(try state.tradeRepository.count(), 30)
        XCTAssertEqual(try setAside(folder), [])
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        let again = await relaunched.unlock(password: password)
        XCTAssertEqual(again, .unlocked)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// A file that can't be read from disk (here: no permission) is a disk problem, not an
    /// unreadable journal: leave it in place and say so
    func testJournalThatCantBeReadFromDiskIsLeftInPlace() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let onDisk = try await savedJournal(vault, folder, lockOn: false)
        let path = journal(folder).path
        XCTAssertEqual(chmod(path, 0), 0)
        addTeardownBlock { chmod(path, 0o600) }

        let state = makeState(vault, folder)
        XCTAssertTrue(state.isDatabaseFailed)
        XCTAssertTrue(try XCTUnwrap(state.databaseError).contains("The file was left untouched"))
        XCTAssertEqual(try setAside(folder), [])
        XCTAssertFalse(state.database.isPersistent)
        state.shutdown()

        XCTAssertEqual(chmod(path, 0o600), 0)
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)
        let relaunched = makeState(vault, folder)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// The other side: a file that doesn't decrypt is still set aside (kept) and a new one
    /// started, and the message names the kept file
    func testUndecryptableJournalIsStillSetAside() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        try Data(repeating: 7, count: 4096).write(to: journal(folder))
        _ = try vault.plainKey(createIfMissing: true)

        let state = makeState(vault, folder)
        XCTAssertFalse(state.isDatabaseFailed)
        XCTAssertEqual(try setAside(folder).count, 1)
        XCTAssertTrue(try XCTUnwrap(state.databaseError).contains(".unreadable-"))
        state.shutdown()
    }

    // MARK: - Finding 3: one running copy per data folder

    /// A second copy (same bundle ID at another path, `open -n`, …) opens nothing: no
    /// journal, no save, so it can't overwrite the first copy's changes
    func testSecondCopyOpensNothing() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let first = makeState(vault, folder)
        XCTAssertFalse(first.isAnotherCopyRunning)
        _ = try first.tradeRepository.bulkInsert(sampleTrades())
        let onDisk = try Data(contentsOf: journal(folder))

        let second = makeState(vault, folder)
        XCTAssertTrue(second.isAnotherCopyRunning)
        XCTAssertFalse(second.database.isPersistent, "Nothing opened")
        XCTAssertFalse(second.isLocked)
        XCTAssertEqual(try second.tradeRepository.count(), 0)
        _ = try second.tradeRepository.bulkInsert([{ var t = sampleTrades()[0]; t.ticket = 99; return t }()])
        second.shutdown()
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk, "The second copy wrote nothing")

        _ = try first.tradeRepository.bulkInsert([{ var t = sampleTrades()[0]; t.ticket = 77; return t }()])
        first.shutdown()
        let third = makeState(vault, folder)
        XCTAssertFalse(third.isAnotherCopyRunning, "Released when the first copy quit")
        XCTAssertEqual(try third.tradeRepository.count(), 31)
        third.shutdown()
    }

    func testInstanceLockIsExclusiveAndReleased() throws {
        let folder = try makeScratchFolder()
        guard case .acquired(let lock) = InstanceLock.acquire(in: folder) else { return XCTFail("first") }
        guard case .heldElsewhere = InstanceLock.acquire(in: folder) else { return XCTFail("second") }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: folder.appendingPathComponent(InstanceLock.fileName).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        lock.release()
        guard case .acquired(let again) = InstanceLock.acquire(in: folder) else { return XCTFail("after release") }
        again.release()
    }

    // MARK: - Dojix #5: a restore racing the final save

    /// The app locks while a backup is being checked: the journal's final save runs first.
    /// The restore must then be refused, not committed to memory and never saved (which
    /// reported "Backup restored" while the restored rows were lost).
    func testRestoreAfterTheFinalSaveIsRefused() throws {
        let folder = try makeScratchFolder()
        let manager = try DatabaseManager(path: journal(folder).path, key: SymmetricKey(size: .bits256))
        _ = try TradeRepository(database: manager).bulkInsert(sampleTrades())
        let backup = try backupBytes(with: Array(sampleTrades().prefix(5)))

        manager.finishSaving() // what closing does first; the queue itself is still open
        let onDisk = try Data(contentsOf: journal(folder))
        XCTAssertThrowsError(try BackupService.restore(from: backup, password: nil, into: manager)) {
            XCTAssertEqual($0 as? DatabaseManager.StorageError, .closed)
        }
        XCTAssertEqual(try TradeRepository(database: manager).count(), 30, "Nothing restored into memory")
        XCTAssertEqual(try Data(contentsOf: journal(folder)), onDisk)
        manager.close()
    }
}
