import GRDB
import XCTest
@testable import Greenwick

/// F6 (and Dojix F7/F8 via restore): a backup is a whole database chosen by the user.
/// It must be validated in memory and refused with a clear message, never copied over
/// the journal unchecked.
final class RestoreValidationTests: XCTestCase {

    private func makeLiveJournal() throws -> DatabaseManager {
        let live = try DatabaseManager(inMemory: true)
        var mine = sampleTrades()[0]
        mine.ticket = 42
        mine.symbol = "MINE"
        mine.isSample = false
        XCTAssertEqual(try TradeRepository(database: live).bulkInsert([mine]), 1)
        return live
    }

    private func assertRefused(_ bytes: Data, _ expected: BackupValidator.ValidationError? = nil,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let live = try makeLiveJournal()
        XCTAssertThrowsError(try BackupService.restore(from: bytes, password: nil, into: live),
                             file: file, line: line) { error in
            if let expected {
                XCTAssertEqual(error as? BackupValidator.ValidationError, expected, file: file, line: line)
            }
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }
        let symbols = try TradeRepository(database: live).fetchAll().map(\.symbol)
        XCTAssertEqual(symbols, ["MINE"], "The journal must be untouched", file: file, line: line)
    }

    func testValidBackupReplacesTheJournal() throws {
        let live = try makeLiveJournal()
        try BackupService.restore(from: try backupBytes(with: sampleTrades()), password: nil, into: live)
        let trades = try TradeRepository(database: live).fetchAll()
        XCTAssertEqual(trades.count, 30)
        XCTAssertFalse(trades.contains { $0.symbol == "MINE" })
    }

    func testPasswordProtectedBackupRestores() throws {
        let live = try makeLiveJournal()
        let sealed = try BackupEncryption.encrypt(try backupBytes(with: sampleTrades()), password: "pw-123456")
        XCTAssertThrowsError(try BackupService.restore(from: sealed, password: nil, into: live))
        try BackupService.restore(from: sealed, password: "pw-123456", into: live)
        XCTAssertEqual(try TradeRepository(database: live).count(), 30)
    }

    /// A generated column doesn't show in `PRAGMA table_info`, so it slipped past the
    /// "same schema as the app" check, and it is computed for every row read (a
    /// `zeroblob(1000000000)` column makes the restore allocate a gigabyte per trade)
    func testHiddenGeneratedColumnsAreRefused() throws {
        let bytes = try backupBytes(with: sampleTrades(), sql: [
            "ALTER TABLE trades ADD COLUMN padding BLOB GENERATED ALWAYS AS (zeroblob(16)) VIRTUAL",
        ])
        try assertRefused(bytes, .unexpectedSchema("table trades definition"))
    }

    /// F6: two rows with durationMin = Int.max used to crash every launch
    func testOverflowingDurationsAreRefused() throws {
        let bytes = try backupBytes(with: sampleTrades(), sql: [
            "UPDATE trades SET durationMin = 9223372036854775807 WHERE rowid IN (1, 2)",
        ])
        try assertRefused(bytes, .invalidRow(table: "trades", row: 1, fields: ["durationMin"]))
    }

    func testOutOfRangeNumbersAreRefused() throws {
        for sql in [
            "UPDATE trades SET shares = 1e-12 WHERE rowid = 3",
            "UPDATE trades SET netProfit = '-1000000000000000000000' WHERE rowid = 3",
            "UPDATE trades SET hour = 99 WHERE rowid = 3",
            "UPDATE trades SET volume = -5 WHERE rowid = 3",
            "UPDATE trades SET rMultiple = 1e300 WHERE rowid = 3",
            "UPDATE trades SET direction = 'SIDEWAYS' WHERE rowid = 3",
            "UPDATE trades SET shares = 'many' WHERE rowid = 3",
        ] {
            try assertRefused(try backupBytes(with: sampleTrades(), sql: [sql]))
        }
    }

    /// Dojix F7: a bare CR in a symbol split exported CSV rows
    func testControlCharactersInTextAreRefused() throws {
        try assertRefused(try backupBytes(with: sampleTrades(), sql: [
            "UPDATE trades SET symbol = 'AAPL' || char(13) || '=cmd()' WHERE rowid = 1",
        ]), .invalidRow(table: "trades", row: 1, fields: ["symbol"]))
    }

    /// Dojix F8: ".." as a screenshot name pointed the delete at the shared folder
    func testForeignScreenshotNamesAreRefused() throws {
        for name in ["..", ".", ".hidden", "../x.jpg", "shot.jpg"] {
            try assertRefused(try backupBytes(with: sampleTrades(), sql: [
                "UPDATE trades SET screenshots = '\(name)' WHERE rowid = 1",
            ]), .invalidRow(table: "trades", row: 1, fields: ["screenshots"]))
        }
        // The app's own names are fine
        let live = try makeLiveJournal()
        try BackupService.restore(from: try backupBytes(with: sampleTrades(), sql: [
            "UPDATE trades SET screenshots = '\(UUID().uuidString).jpg' WHERE rowid = 1",
        ]), password: nil, into: live)
        XCTAssertEqual(try TradeRepository(database: live).count(), 30)
    }

    func testTriggersViewsAndForeignTablesAreRefused() throws {
        try assertRefused(try backupBytes(with: sampleTrades(), sql: [
            "CREATE TRIGGER wipe AFTER INSERT ON trades BEGIN DELETE FROM trades; END",
        ]))
        try assertRefused(try backupBytes(with: sampleTrades(), sql: [
            "CREATE VIEW v AS SELECT * FROM trades",
        ]))
        try assertRefused(try backupBytes(with: sampleTrades(), sql: [
            "CREATE TABLE extra (x)",
        ]))
    }

    /// An allowed table name with different columns, constraints or defaults
    func testAlteredTablesAreRefused() throws {
        for sql in [
            ["ALTER TABLE trades ADD COLUMN payload TEXT DEFAULT 'x'"],
            ["ALTER TABLE settings RENAME TO settings_old",
             "CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT 'evil')",
             "DROP TABLE settings_old"],
            ["CREATE INDEX idx_extra ON trades(notes)"],
            ["DROP INDEX idx_trades_symbol"],
        ] {
            try assertRefused(try backupBytes(with: sampleTrades(), sql: sql))
        }
    }

    /// A trigger inside the backup must never reach the journal
    func testTriggerNeverLandsInTheJournal() throws {
        let live = try makeLiveJournal()
        let bytes = try backupBytes(with: sampleTrades(), sql: [
            "CREATE TRIGGER evil AFTER UPDATE ON trades BEGIN DELETE FROM trades; END",
        ])
        XCTAssertThrowsError(try BackupService.restore(from: bytes, password: nil, into: live))
        let objects = try live.dbQueue.read { try String.fetchAll($0, sql: "SELECT type || ' ' || name FROM sqlite_master") }
        XCTAssertFalse(objects.contains { $0.hasPrefix("trigger") }, "\(objects)")

        // After a good restore the journal's schema is still exactly the app's own
        let reference = try DatabaseManager(inMemory: true)
        let expected = try reference.dbQueue.read { try String.fetchAll($0, sql: "SELECT type || ' ' || name || ' ' || coalesce(sql, '') FROM sqlite_master ORDER BY name") }
        try BackupService.restore(from: try backupBytes(with: sampleTrades()), password: nil, into: live)
        let actual = try live.dbQueue.read { try String.fetchAll($0, sql: "SELECT type || ' ' || name || ' ' || coalesce(sql, '') FROM sqlite_master ORDER BY name") }
        XCTAssertEqual(actual.filter { !$0.contains("sqlite_sequence") }, expected.filter { !$0.contains("sqlite_sequence") })
    }

    func testBackupFromANewerVersionIsRefused() throws {
        try assertRefused(try backupBytes(with: sampleTrades(), sql: [
            "INSERT INTO grdb_migrations (identifier) VALUES ('v99_fromTheFuture')",
        ]), .newerVersion)
    }

    func testOlderBackupIsMigratedAfterValidation() throws {
        // A backup made before the settings table and the sample flag existed, holding the
        // old-style sample trades (comment "Demo") and one real trade
        var real = sampleTrades()[0]
        real.ticket = 123
        real.isSample = false
        real.comment = "Demo"
        let bytes = try backupBytes(with: sampleTrades() + [real], sql: [
            "DROP TABLE settings",
            "ALTER TABLE trades DROP COLUMN isSample",
            "UPDATE trades SET comment = 'Demo'",
            "DELETE FROM grdb_migrations WHERE identifier IN ('v4_createSettings', 'v5_markSampleTrades')",
        ])
        let live = try makeLiveJournal()
        try BackupService.restore(from: bytes, password: nil, into: live)
        let repo = TradeRepository(database: live)
        XCTAssertEqual(try repo.count(), 31)
        XCTAssertEqual(try repo.sampleTradeCount(), 30, "Old sample trades are recognised")
        XCTAssertEqual(try repo.deleteSampleTrades(), 30)
        XCTAssertEqual(try repo.fetchAll().map(\.ticket), [123])
        XCTAssertTrue(try live.dbQueue.read { try $0.tableExists("settings") })
    }

    func testNonDatabasesAndDamagedFilesAreRefused() throws {
        try assertRefused(Data("Ticket,Symbol\n1,AAPL\n".utf8))
        var damaged = try backupBytes(with: sampleTrades())
        damaged.replaceSubrange(4096..<8192, with: Data(repeating: 0xAB, count: 4096))
        try assertRefused(damaged)
        try assertRefused(Data(DatabaseEncryption.sqliteMagic + Data(repeating: 0, count: 200)))
    }

    /// A backup taken by an older version is a WAL-mode file: still accepted
    func testWALModeBackupFileIsAccepted() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("old.sjbackup").path
        try backupBytes(with: sampleTrades()).write(to: URL(fileURLWithPath: path))
        let pool = try DatabasePool(path: path)
        try pool.close()
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(bytes[18], 2, "WAL-mode header")
        let live = try makeLiveJournal()
        try BackupService.restore(from: bytes, password: nil, into: live)
        XCTAssertEqual(try TradeRepository(database: live).count(), 30)
    }
}
