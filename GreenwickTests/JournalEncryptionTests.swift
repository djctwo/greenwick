import CryptoKit
import GRDB
import XCTest
@testable import Greenwick

/// F2: the journal must never sit on disk in plaintext — not while Greenwick runs, not
/// after a crash, and not as a leftover copy.
final class JournalEncryptionTests: XCTestCase {

    private func plaintextFiles(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { DatabaseEncryption.fileIsPlaintext(at: folder.appendingPathComponent($0).path) }
    }

    func testOpenJournalIsNeverWrittenInPlaintext() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let key = SymmetricKey(size: .bits256)

        let db = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(try TradeRepository(database: db).bulkInsert(sampleTrades()), 30)

        // While open (no close, no quit): only the sealed file, no WAL/SHM, owner-only
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Greenwick.sqlite"])
        XCTAssertEqual(plaintextFiles(in: folder), [])
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let sealed = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertFalse(sealed.range(of: Data("NVDA".utf8)) != nil, "Trade text must not be readable on disk")

        // A crash right now loses nothing: a second open (as after a relaunch) sees every trade
        let reopened = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 30)

        // Every later commit is saved too
        let first = try XCTUnwrap(try TradeRepository(database: db).fetchAll().first?.id)
        try TradeRepository(database: db).updateNotes(tradeId: first, notes: "after open")
        let again = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(try TradeRepository(database: again).fetchAll().first { $0.id == first }?.notes, "after open")
        db.close()
        reopened.close()
        again.close()
        XCTAssertEqual(plaintextFiles(in: folder), [])
    }

    /// Unclean shutdown of an older version: plaintext main file + a WAL holding changes
    /// that were never checkpointed. Must be encrypted at once, keeping the WAL's changes.
    func testPlaintextJournalFoundAtLaunchIsEncryptedImmediately() throws {
        let folder = try makeScratchFolder()
        let crashed = folder.appendingPathComponent("live", isDirectory: true)
        try FileManager.default.createDirectory(at: crashed, withIntermediateDirectories: true)
        let livePath = crashed.appendingPathComponent("Greenwick.sqlite").path

        // An older Greenwick: plaintext WAL-mode journal, killed while open
        try backupBytes(with: sampleTrades()).write(to: URL(fileURLWithPath: livePath))
        let pool = try DatabasePool(path: livePath)
        try pool.write { db in try db.execute(sql: "PRAGMA wal_autocheckpoint = 0") }
        try pool.write { db in try db.execute(sql: "UPDATE trades SET notes = 'only in the WAL'") }
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        for suffix in ["", "-wal", "-shm"] { // copied while open = what a crash leaves behind
            try FileManager.default.copyItem(atPath: livePath + suffix, toPath: path + suffix)
        }
        try pool.close()
        XCTAssertTrue(DatabaseEncryption.fileIsPlaintext(at: path))

        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: path, key: key)
        XCTAssertFalse(DatabaseEncryption.fileIsPlaintext(at: path), "Must be encrypted before use")
        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path + suffix), "\(suffix) left behind")
        }
        let trades = try TradeRepository(database: db).fetchAll()
        XCTAssertEqual(trades.count, 30)
        XCTAssertTrue(trades.allSatisfy { $0.notes == "only in the WAL" }, "WAL changes must survive")
        db.close()
    }

    func testWrongKeyNeverDestroysTheJournal() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let db = try DatabaseManager(path: path, key: SymmetricKey(size: .bits256))
        _ = try TradeRepository(database: db).bulkInsert(sampleTrades())
        db.close()
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        XCTAssertThrowsError(try DatabaseManager(path: path, key: SymmetricKey(size: .bits256)))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), before)
    }

    /// Lock off, but the Keychain key can't be read: never generate a new key over the
    /// existing journal (that would make it unreadable forever)
    func testMissingKeyLeavesTheJournalUntouched() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let (vault, store, _) = makeVault()
        let first = AppState(vault: vault, databasePath: path, screenshotsDirectory: folder)
        _ = try first.tradeRepository.bulkInsert(sampleTrades())
        first.shutdown()
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        store.delete(AppLockVault.Account.plainKey)
        let second = AppState(vault: vault, databasePath: path, screenshotsDirectory: folder)
        XCTAssertTrue(second.isDatabaseFailed)
        XCTAssertNil(store.read(AppLockVault.Account.plainKey), "No replacement key may be created")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), before)
    }

    /// An undecryptable journal is set aside (still encrypted), never deleted
    func testUnreadableJournalIsKeptAsideEncrypted() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        let garbage = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try garbage.write(to: URL(fileURLWithPath: path))
        let (vault, store, _) = makeVault()
        _ = try vault.plainKey(createIfMissing: true)
        XCTAssertNotNil(store.read(AppLockVault.Account.plainKey))

        let state = AppState(vault: vault, databasePath: path, screenshotsDirectory: folder)
        XCTAssertFalse(state.isDatabaseFailed)
        XCTAssertNotNil(state.databaseError)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let aside = try XCTUnwrap(names.first { $0.hasPrefix("Greenwick.sqlite.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(aside)), garbage)
        XCTAssertEqual(plaintextFiles(in: folder), [])
        state.shutdown()
    }

    func testStrayPlaintextCopiesFromOlderVersionsAreRemoved() throws {
        let folder = try makeScratchFolder()
        let stray = folder.appendingPathComponent("greenwick-restore-\(UUID().uuidString).sqlite")
        let other = folder.appendingPathComponent("unrelated.sqlite")
        try backupBytes(with: sampleTrades()).write(to: stray)
        try Data("keep".utf8).write(to: other)
        DatabaseEncryption.removeStrayTemporaryCopies(in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testBackupExportIsASnapshotWithoutTemporaryFiles() throws {
        let db = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: db).bulkInsert(sampleTrades())
        let bytes = try db.serializedSnapshot()
        XCTAssertTrue(DatabaseEncryption.isPlaintextSQLite(bytes))
        XCTAssertEqual(try BackupValidator.validatedContents(from: bytes).trades.count, 30)
    }
}
