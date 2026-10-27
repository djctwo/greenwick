import CryptoKit
import XCTest
@testable import Greenwick

/// A Keychain that refuses every write (full, locked, or access denied)
final class RefusingSecretStore: SecretStore, @unchecked Sendable {
    func lookup(_ account: String) -> SecretLookup { .absent }
    func write(_ data: Data, account: String) -> Bool { false }
    func delete(_ account: String) {}
}

/// Rollback protection: every save numbers the journal (generation, in the sealed file's
/// header and in the Keychain). An older copy put in place of the journal is not opened
/// silently.
final class RollbackProtectionTests: XCTestCase {
    private let password = "correct-horse-42"

    private func path(_ folder: URL) -> String { folder.appendingPathComponent("Greenwick.sqlite").path }

    private func fileStamp(_ path: String, key: SymmetricKey) throws -> JournalStamp? {
        try JournalFormat.open(Data(contentsOf: URL(fileURLWithPath: path)), key: key).stamp
    }

    @MainActor
    private func makeState(_ vault: AppLockVault, _ folder: URL) -> AppState {
        AppState(vault: vault, databasePath: path(folder),
                 screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true))
    }

    /// Journal with the 30 sample trades, a copy of that file, then one more trade saved
    /// over it. Returns the older copy's bytes.
    @MainActor
    private func journalWithAnOlderCopy(_ state: AppState) throws -> Data {
        XCTAssertEqual(try state.tradeRepository.bulkInsert(sampleTrades()), 30)
        let older = try Data(contentsOf: URL(fileURLWithPath: state.databasePath))
        var extra = sampleTrades()[0]
        extra.ticket = 77
        XCTAssertEqual(try state.tradeRepository.bulkInsert([extra]), 1)
        return older
    }

    // MARK: - Format and counting

    func testEverySaveRaisesTheGenerationInTheFileAndTheKeychain() throws {
        let folder = try makeScratchFolder()
        let ledger = JournalLedger(store: MemorySecretStore())
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        let first = try XCTUnwrap(try fileStamp(path(folder), key: key))
        XCTAssertEqual(first.generation, 1)
        XCTAssertEqual(first.epoch.count, 16)
        XCTAssertEqual(ledger.read()?.stamp, first)
        XCTAssertEqual(ledger.read()?.fileHash,
                       JournalFormat.fingerprint(of: try Data(contentsOf: URL(fileURLWithPath: path(folder)))))

        _ = try TradeRepository(database: db).bulkInsert(sampleTrades())
        let second = try XCTUnwrap(try fileStamp(path(folder), key: key))
        XCTAssertGreaterThan(second.generation, first.generation)
        XCTAssertEqual(second.epoch, first.epoch, "Same line of saves")
        XCTAssertEqual(ledger.read()?.stamp, second, "The Keychain holds the latest save")
        XCTAssertEqual(db.lastSavedStamp, second)
        db.close()
    }

    /// The header is AES-GCM associated data: the generation can't be raised without the key
    func testGenerationCantBeChangedWithoutTheKey() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: path(folder), key: key)
        db.close()
        var bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path(folder))))
        XCTAssertEqual(Data(bytes[0..<4]), Data("GWJN".utf8))
        bytes[JournalFormat.headerLength - 9] ^= 0x40 // generation, low byte
        XCTAssertThrowsError(try JournalFormat.open(Data(bytes), key: key))
        bytes[JournalFormat.headerLength - 9] ^= 0x40
        bytes[6] ^= 0x01 // epoch
        XCTAssertThrowsError(try JournalFormat.open(Data(bytes), key: key))
    }

    // MARK: - Detection

    @MainActor
    func testOlderCopyIsDetectedAndLeftUntouched() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        let older = try journalWithAnOlderCopy(state)
        state.shutdown()
        try older.write(to: URL(fileURLWithPath: path(folder)))

        let relaunched = makeState(vault, folder)
        let notice = try XCTUnwrap(relaunched.olderJournal, "An older copy must not open silently")
        XCTAssertLessThan(try XCTUnwrap(notice.file).generation, notice.lastSaved.generation)
        XCTAssertTrue(notice.question.hasPrefix("This journal is older than the last one this Mac saved (saved "))
        XCTAssertTrue(notice.question.hasSuffix("). Open it anyway?"))
        XCTAssertFalse(relaunched.database.isPersistent, "Not opened")
        XCTAssertFalse(relaunched.isDatabaseFailed)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(folder))), older, "Not changed or set aside")
        try assertOnlyTheJournal(in: folder)
        relaunched.shutdown()
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(folder))), older, "Quitting changes nothing")
    }

    /// App Lock off: opening needs an explicit confirmation, then the Keychain follows the file
    @MainActor
    func testOlderCopyOpensAfterConfirmationAndTheKeychainFollows() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        let older = try journalWithAnOlderCopy(state)
        state.shutdown()
        try older.write(to: URL(fileURLWithPath: path(folder)))

        let relaunched = makeState(vault, folder)
        XCTAssertNotNil(relaunched.olderJournal)
        let lastBefore = try XCTUnwrap(vault.ledger.read()).stamp
        XCTAssertTrue(relaunched.openOlderJournal())
        XCTAssertNil(relaunched.olderJournal)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30, "The older copy's content")
        let key = try XCTUnwrap(relaunched.database.encryptionKey)
        let now = try XCTUnwrap(try fileStamp(path(folder), key: key))
        XCTAssertEqual(vault.ledger.read()?.stamp, now, "The Keychain follows the opened file")
        XCTAssertGreaterThan(now.generation, lastBefore.generation, "The counter never goes down")
        XCTAssertNotEqual(now.epoch, lastBefore.epoch, "A new line of saves starts")
        relaunched.shutdown()

        let again = makeState(vault, folder)
        XCTAssertNil(again.olderJournal, "Accepted once, no second warning")
        XCTAssertEqual(try again.tradeRepository.count(), 30)
        again.shutdown()
    }

    /// App Lock on: the right password reveals the warning; opening needs the password again
    @MainActor
    func testLockedOlderCopyNeedsThePasswordAgain() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try await state.enableAppLock(password: password)
        let older = try journalWithAnOlderCopy(state)
        state.shutdown()
        try older.write(to: URL(fileURLWithPath: path(folder)))

        let relaunched = makeState(vault, folder)
        XCTAssertTrue(relaunched.isLocked)
        let first = await relaunched.unlock(password: password)
        XCTAssertEqual(first, .olderJournal)
        XCTAssertNotNil(relaunched.olderJournal)
        XCTAssertTrue(relaunched.isLocked)
        XCTAssertFalse(relaunched.database.isPersistent)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(folder))), older)

        XCTAssertFalse(relaunched.openOlderJournal(), "With App Lock on, a confirmation alone is not enough")
        let wrong = await relaunched.unlock(password: "wrong-password", acceptOlderJournal: true)
        XCTAssertEqual(wrong, .wrongPassword)
        XCTAssertFalse(relaunched.database.isPersistent)

        let opened = await relaunched.unlock(password: password, acceptOlderJournal: true)
        XCTAssertEqual(opened, .unlocked)
        XCTAssertFalse(relaunched.isLocked)
        XCTAssertNil(relaunched.olderJournal)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// Forgot password with Touch ID / Mac password on an older copy: the lock is removed
    /// (the key decrypted the file) but the older journal still needs a confirmation
    @MainActor
    func testRecoveryOnAnOlderCopyStillAsks() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try await state.enableAppLock(password: password)
        let older = try journalWithAnOlderCopy(state)
        state.shutdown()
        try older.write(to: URL(fileURLWithPath: path(folder)))

        let relaunched = makeState(vault, folder)
        try await relaunched.recoverWithDeviceOwner()
        XCTAssertFalse(relaunched.isAppLockEnabled)
        XCTAssertNotNil(relaunched.olderJournal)
        XCTAssertFalse(relaunched.database.isPersistent)
        XCTAssertTrue(relaunched.openOlderJournal())
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    /// After the owner opens an older copy, the newer copy they abandoned must not come back
    /// silently: it has a higher generation than the copy they chose, but another epoch
    @MainActor
    func testAbandonedNewerCopyIsCaughtAfterOpeningAnOlderOne() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        let older = try journalWithAnOlderCopy(state)
        state.shutdown()
        let abandoned = try Data(contentsOf: URL(fileURLWithPath: path(folder))) // 31 trades
        try older.write(to: URL(fileURLWithPath: path(folder)))

        let chosen = makeState(vault, folder)
        XCTAssertTrue(chosen.openOlderJournal())
        chosen.shutdown()
        try abandoned.write(to: URL(fileURLWithPath: path(folder)))

        let replayed = makeState(vault, folder)
        let notice = try XCTUnwrap(replayed.olderJournal, "The abandoned copy must not open silently")
        XCTAssertEqual(notice.reason, .differentCopy)
        XCTAssertFalse(replayed.database.isPersistent)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(folder))), abandoned, "Untouched")
        replayed.shutdown()
    }

    /// Two files with the same epoch and generation but different content (only the
    /// recorded one is the last save): the other is caught by the file fingerprint
    func testSameGenerationWithDifferentContentIsCaught() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let ledger = JournalLedger(store: MemorySecretStore())
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        _ = try TradeRepository(database: db).bulkInsert(sampleTrades())
        db.close()
        let last = try XCTUnwrap(ledger.read())

        let other = try JournalFormat.seal(try backupBytes(with: []), key: key, stamp: last.stamp)
        try other.write(to: URL(fileURLWithPath: path(folder)))
        XCTAssertThrowsError(try DatabaseManager(path: path(folder), key: key, ledger: ledger)) {
            XCTAssertEqual(($0 as? DatabaseManager.OlderJournal)?.reason, .differentCopy)
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path(folder))), other)
    }

    /// Normal relaunches never raise the question
    func testNormalSavesAndRelaunchesRaiseNoAlarm() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let ledger = JournalLedger(store: MemorySecretStore())
        for round in 0..<3 {
            let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
            var trade = sampleTrades()[round]
            trade.ticket = 500 + Int64(round)
            _ = try TradeRepository(database: db).bulkInsert([trade])
            db.close()
        }
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        XCTAssertEqual(try TradeRepository(database: db).count(), 3)
        db.close()
    }

    // MARK: - Accepted without a question

    /// Keychain lost or behind (e.g. its write failed): a newer file is fine and the
    /// Keychain catches up
    func testNewerFileIsAcceptedAndTheKeychainUpdated() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let ledger = JournalLedger(store: MemorySecretStore())
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        _ = try TradeRepository(database: db).bulkInsert(sampleTrades())
        db.close()
        let onDisk = try XCTUnwrap(try fileStamp(path(folder), key: key))

        let behind = JournalStamp(epoch: onDisk.epoch, generation: 1, savedAt: Date(timeIntervalSince1970: 0))
        for stale in [nil, JournalLedger.Entry(stamp: behind, fileHash: Data([1]))] {
            ledger.remove()
            if let stale { ledger.record(stale) }
            let reopened = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
            XCTAssertEqual(try TradeRepository(database: reopened).count(), 30)
            let caughtUp = try XCTUnwrap(ledger.read()).stamp
            XCTAssertGreaterThan(caughtUp.generation, onDisk.generation)
            XCTAssertEqual(caughtUp.epoch, onDisk.epoch)
            reopened.close()
        }
    }

    /// Journals sealed before generations existed count as generation 0
    func testJournalFromBeforeThisVersionStartsCounting() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        try DatabaseEncryption.writeSealed(try backupBytes(with: sampleTrades()), to: path(folder), key: key)
        XCTAssertNil(try JournalFormat.open(Data(contentsOf: URL(fileURLWithPath: path(folder))), key: key).stamp)

        let ledger = JournalLedger(store: MemorySecretStore())
        ledger.record(JournalLedger.Entry(
            stamp: JournalStamp(epoch: JournalStamp.newEpoch(), generation: 5, savedAt: Date()), fileHash: Data()))
        XCTAssertThrowsError(try DatabaseManager(path: path(folder), key: key, ledger: ledger)) {
            let older = $0 as? DatabaseManager.OlderJournal
            XCTAssertEqual(older?.reason, .older, "Unnumbered = generation 0 < 5")
            XCTAssertNil(older?.file)
        }

        ledger.remove() // the normal upgrade: nothing recorded yet
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        XCTAssertEqual(try TradeRepository(database: db).count(), 30)
        XCTAssertEqual(try fileStamp(path(folder), key: key)?.generation, 1)
        XCTAssertEqual(ledger.read()?.stamp.generation, 1)
        db.close()
    }

    /// A brand-new journal file (first launch, after "erase all", or after an unreadable
    /// one was set aside) continues after the recorded generation: no false alarm
    func testNewJournalContinuesAfterTheRecordedGeneration() throws {
        let folder = try makeScratchFolder()
        let ledger = JournalLedger(store: MemorySecretStore())
        let recorded = JournalStamp(epoch: JournalStamp.newEpoch(), generation: 40, savedAt: Date())
        ledger.record(JournalLedger.Entry(stamp: recorded, fileHash: Data()))
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        XCTAssertEqual(try fileStamp(path(folder), key: key)?.generation, 41)
        XCTAssertEqual(try fileStamp(path(folder), key: key)?.epoch, recorded.epoch)
        db.close()
        XCTAssertNoThrow(try DatabaseManager(path: path(folder), key: key, ledger: ledger).close())
    }

    @MainActor
    func testRestoringABackupSetsTheGenerationWithoutAFalseAlarm() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        let before = try XCTUnwrap(vault.ledger.read()).stamp.generation
        let backup = try state.database.serializedSnapshot() // an older state of this journal

        var extra = sampleTrades()[0]
        extra.ticket = 77
        _ = try state.tradeRepository.bulkInsert([extra])
        try BackupService.restore(from: backup, password: nil, into: state.database)
        XCTAssertGreaterThan(try XCTUnwrap(vault.ledger.read()).stamp.generation, before + 1)
        state.shutdown()

        let relaunched = makeState(vault, folder)
        XCTAssertNil(relaunched.olderJournal)
        XCTAssertEqual(try relaunched.tradeRepository.count(), 30)
        relaunched.shutdown()
    }

    @MainActor
    func testEraseAllLocalDataStartsAFreshCount() async throws {
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = makeState(vault, folder)
        _ = try state.tradeRepository.bulkInsert(sampleTrades())
        _ = try await state.enableAppLock(password: password)
        XCTAssertGreaterThan(try XCTUnwrap(vault.ledger.read()).stamp.generation, 2)
        state.lock()
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }

        try await state.eraseAllLocalData()
        XCTAssertEqual(vault.ledger.read()?.stamp.generation, 1, "The new journal's first save")
        state.shutdown()
        let relaunched = makeState(vault, folder)
        XCTAssertNil(relaunched.olderJournal)
        relaunched.shutdown()
    }

    // MARK: - Keychain failure

    /// The Keychain refuses the generation: logged, and the journal is saved and reopens
    func testRefusedKeychainWriteLosesNothing() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let ledger = JournalLedger(store: RefusingSecretStore())
        let db = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        XCTAssertEqual(try TradeRepository(database: db).bulkInsert(sampleTrades()), 30)
        XCTAssertNil(db.lastSaveError, "Saving the journal itself worked")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(try fileStamp(path(folder), key: key)).generation, 2)
        db.close()

        let reopened = try DatabaseManager(path: path(folder), key: key, ledger: ledger)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 30)
        reopened.close()
    }
}
