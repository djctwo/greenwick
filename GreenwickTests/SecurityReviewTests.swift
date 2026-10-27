import CryptoKit
import Foundation
import GRDB
import Security
import OSLog
import XCTest
@testable import Greenwick

/// Findings of the second security review (adversarial audit, secrets scan, STRIDE model)
final class SecurityReviewTests: XCTestCase {

    private func journalPath(in folder: URL) -> String {
        folder.appendingPathComponent("Greenwick.sqlite").path
    }

    // MARK: - A10: a failed save must not be silent

    /// The journal lives in memory and is sealed to disk after every commit. When that
    /// write fails (disk full, folder not writable), the user must be told: otherwise every
    /// later change exists only in memory and is lost at quit without a word.
    func testFailedSaveIsReportedToTheApp() throws {
        let folder = try makeScratchFolder()
        let manager = try DatabaseManager(path: journalPath(in: folder), key: SymmetricKey(size: .bits256))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }

        let reported = expectation(forNotification: Notification.Name("GreenwickJournalSaveFailed"), object: nil)
        XCTAssertEqual(try TradeRepository(database: manager).bulkInsert(sampleTrades()), 30)
        wait(for: [reported], timeout: 3)
        XCTAssertNotNil(manager.lastSaveError)
        manager.close()
    }

    // MARK: - A04: prop firm account size and limits live in the encrypted journal

    /// Snyk `swift/InsecureStorage`: the account size and loss limits were stored in the
    /// preferences plist, readable by anyone even while App Lock is on
    func testPropFirmSettingsAreSealedInTheJournal() throws {
        let folder = try makeScratchFolder()
        let path = journalPath(in: folder)
        let key = SymmetricKey(size: .bits256)
        let journal = try DatabaseManager(path: path, key: key)
        let mine = PropFirmSettings(accountSize: 123_457, profitTarget: 6, maxDailyLoss: 3, maxTotalDrawdown: 7.5)
        try mine.save(to: journal)
        journal.close()

        let sealed = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertFalse(DatabaseEncryption.isPlaintextSQLite(sealed))
        XCTAssertNil(sealed.range(of: Data("123457".utf8)), "Only ciphertext on disk")
        let reopened = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(PropFirmSettings.load(from: reopened), mine)
        reopened.close()
    }

    func testPropFirmPreferencesFromOlderVersionsMoveIntoTheJournal() throws {
        let suite = "gw-sf-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(250_000.0, forKey: PropFirmSettings.Key.accountSize)
        defaults.set(4.0, forKey: PropFirmSettings.Key.maxDailyLoss)

        let folder = try makeScratchFolder()
        let journal = try DatabaseManager(path: journalPath(in: folder), key: SymmetricKey(size: .bits256))
        PropFirmSettings.migrateFromPreferences(defaults, into: journal)
        for key in PropFirmSettings.Key.all { XCTAssertNil(defaults.object(forKey: key), key) }
        XCTAssertEqual(PropFirmSettings.load(from: journal),
                       PropFirmSettings(accountSize: 250_000, profitTarget: 8, maxDailyLoss: 4, maxTotalDrawdown: 10))

        // The locked-app placeholder (in memory only) never takes them out of preferences
        defaults.set(1.0, forKey: PropFirmSettings.Key.profitTarget)
        PropFirmSettings.migrateFromPreferences(defaults, into: try DatabaseManager(inMemory: true))
        XCTAssertEqual(defaults.double(forKey: PropFirmSettings.Key.profitTarget), 1.0)
        journal.close()
    }

    /// Values from a crafted backup (restored into the settings table) fall back to defaults
    func testHostilePropFirmValuesFallBackToDefaults() throws {
        let journal = try DatabaseManager(inMemory: true)
        for value in ["nan", "inf", "-5", "1e300", "abc", "0"] {
            try journal.dbQueue.write { db in
                for key in PropFirmSettings.Key.all {
                    try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                                   arguments: [key, value])
                }
            }
            XCTAssertEqual(PropFirmSettings.load(from: journal), PropFirmSettings(), value)
        }
        try PropFirmSettings(accountSize: .infinity, profitTarget: 500, maxDailyLoss: -1,
                             maxTotalDrawdown: .nan).save(to: journal)
        XCTAssertEqual(PropFirmSettings.load(from: journal), PropFirmSettings())
    }

    // MARK: - A10: a journal is never erased because its schema looks unfamiliar

    /// Debug builds used GRDB's `eraseDatabaseOnSchemaChange` for the live journal. A
    /// source build run from Xcode (default bundle ID = the real data folder) then erased a
    /// journal written by a newer version, and sealed the empty database over it.
    func testJournalFromANewerVersionIsNeverErased() throws {
        let folder = try makeScratchFolder()
        let path = journalPath(in: folder)
        let key = SymmetricKey(size: .bits256)
        let newer = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(try TradeRepository(database: newer).bulkInsert(sampleTrades()), 30)
        try newer.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99_fromANewerVersion')")
            try db.execute(sql: "CREATE INDEX idx_trades_fromANewerVersion ON trades(comment)")
        }
        newer.close()

        let reopened = try DatabaseManager(path: path, key: key)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 30, "The journal must survive")
        reopened.close()
    }

    // MARK: - A10: overwriting a Keychain item never deletes it first

    private func creationDate(of account: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppPaths.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrCreationDate as String] as? Date
    }

    /// Key rotation overwrites the wrapped journal key. Delete-then-add lost the only copy
    /// when the add failed; the item must be updated in place.
    func testOverwritingAKeychainItemUpdatesItInPlace() throws {
        let account = "sf-overwrite-\(UUID().uuidString)"
        let text = "sf-overwrite-text-\(UUID().uuidString)"
        addTeardownBlock {
            KeychainHelper.delete(key: account)
            KeychainHelper.delete(key: text)
        }
        XCTAssertTrue(KeychainHelper.saveData(key: account, value: Data("first".utf8)))
        XCTAssertTrue(KeychainHelper.save(key: text, value: "first"))
        let dataCreated = try XCTUnwrap(creationDate(of: account))
        let textCreated = try XCTUnwrap(creationDate(of: text))
        Thread.sleep(forTimeInterval: 1.2) // creation dates have one-second resolution

        XCTAssertTrue(KeychainHelper.saveData(key: account, value: Data("second".utf8)))
        XCTAssertTrue(KeychainHelper.save(key: text, value: "second"))
        XCTAssertEqual(KeychainHelper.lookupData(key: account), .found(Data("second".utf8)))
        XCTAssertEqual(KeychainHelper.read(key: text), "second")
        XCTAssertEqual(creationDate(of: account), dataCreated, "Updated in place, not deleted and re-added")
        XCTAssertEqual(creationDate(of: text), textCreated, "Updated in place, not deleted and re-added")
    }

    // MARK: - A03: the one dependency is pinned to a commit

    /// No Package.resolved is committed (the Xcode project is generated), so a version pin
    /// alone trusts whatever the tag points to when the package is fetched.
    func testGRDBIsPinnedToACommit() throws {
        let projectFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let spec = try String(contentsOf: projectFile, encoding: .utf8)
        let block = try XCTUnwrap(spec.range(of: "packages:\n  GRDB:"), "GRDB package block")
        let lines = spec[block.upperBound...].split(separator: "\n").prefix(4)
        let pinned = lines.contains { line in
            line.range(of: #"^\s+revision: "?[0-9a-f]{40}"?(\s|$)"#, options: .regularExpression) != nil
        }
        XCTAssertTrue(pinned, "GRDB must be pinned with `revision: <commit>`:\n\(lines.joined(separator: "\n"))")
    }

    // MARK: - Analytics CSV exports

    /// Tickers and sectors come from imported files; the analytics exports must neutralise
    /// them like the journal export does (formula prefixes, commas, control characters).
    func testAnalyticsCSVNeutralisesImportedLabels() {
        func condition(_ dimension: String, _ label: String) -> MetricsCalculator.EdgeCondition {
            MetricsCalculator.EdgeCondition(id: label, dimension: dimension, label: label, profit: -10,
                                            tradeCount: 12, winRate: 10, expectancy: -1, profitFactor: 0.5,
                                            monthlyImpact: -20)
        }
        let rows = WhatToCutAdvisor.csvRows([condition("Symbol", "=HYPERLINK(\"https://evil.example\")"),
                                             condition("Sector", "A,B\r")], totalSavings: -40)
        let csv = AnalyticsCSV.content(rows)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 5, csv)
        XCTAssertEqual(lines[1], "Symbol,\"'=HYPERLINK(\"\"https://evil.example\"\")\",-10.00,10.0,12,-1.00,0.50,-20.00")
        XCTAssertEqual(lines[2], "Sector,\"A,B\",-10.00,10.0,12,-1.00,0.50,-20.00")
        XCTAssertFalse(csv.contains("\r"))
    }
}

/// Same check as in Dojix: the journal writer and the backup export must not follow a
/// planted symlink, must not chmod by path after the rename, and must leave a 0600 file
final class SecureFileWriteTests: XCTestCase {

    private func mode(_ path: String) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// A same-user process plants `Greenwick.sqlite -> victim`; the next save must replace
    /// the link with the sealed journal and leave the victim (content and mode) alone
    func testSealedJournalWriteNeverFollowsAPlantedSymlink() throws {
        let folder = try makeScratchFolder()
        let victim = folder.appendingPathComponent("victim.txt").path
        try Data("victim".utf8).write(to: URL(fileURLWithPath: victim))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: victim)
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: victim)

        let key = SymmetricKey(size: .bits256)
        try DatabaseEncryption.writeSealed(Data("journal".utf8), to: path, key: key)

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: victim)), Data("victim".utf8))
        XCTAssertEqual(try mode(victim), 0o644, "The link target's permissions must not change")
        XCTAssertFalse(isSymlink(path), "The link itself is replaced")
        XCTAssertEqual(try mode(path), 0o600)
        XCTAssertEqual(try DatabaseEncryption.open(Data(contentsOf: URL(fileURLWithPath: path)), key: key),
                       Data("journal".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["Greenwick.sqlite", "victim.txt"], "No temporary file left behind")
    }

    /// The journal file is 0600 from the moment it exists, whatever the umask
    func testSealedJournalIsOwnerOnly() throws {
        let folder = try makeScratchFolder()
        let path = folder.appendingPathComponent("Greenwick.sqlite").path
        try DatabaseEncryption.writeSealed(Data("one".utf8), to: path, key: SymmetricKey(size: .bits256))
        XCTAssertEqual(try mode(path), 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        try DatabaseEncryption.writeSealed(Data("two".utf8), to: path, key: SymmetricKey(size: .bits256))
        XCTAssertEqual(try mode(path), 0o600, "Rewritten owner-only")
    }

    /// A plain backup is a complete readable copy of the journal: owner-only, never through a link
    func testBackupExportIsOwnerOnlyAndNeverFollowsASymlink() throws {
        let folder = try makeScratchFolder()
        let victim = folder.appendingPathComponent("victim.txt").path
        try Data("victim".utf8).write(to: URL(fileURLWithPath: victim))
        let destination = folder.appendingPathComponent("Greenwick_Backup.sjbackup")
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: victim)

        let bytes = try backupBytes(with: sampleTrades())
        try BackupService.writeBackup(bytes, to: destination, password: nil)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: victim)), Data("victim".utf8))
        XCTAssertFalse(isSymlink(destination.path))
        XCTAssertEqual(try mode(destination.path), 0o600)
        XCTAssertEqual(try Data(contentsOf: destination), bytes)

        let sealed = folder.appendingPathComponent("Greenwick_Backup.sjbackup-enc")
        try BackupService.writeBackup(bytes, to: sealed, password: "pw-123456")
        XCTAssertEqual(try mode(sealed.path), 0o600)
    }
}

/// STRIDE repudiation / OWASP A09: App Lock events must leave a trace in the unified log
/// (Console.app, subsystem com.greenwick), so the owner can see that someone tried passwords
/// or removed the lock while they were away. No password or key is ever logged.
final class SecurityEventLogTests: XCTestCase {
    private let password = "correct-horse-42"

    private func appLockMessages(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "com.greenwick" && $0.category == "AppState" }
            .map(\.composedMessage)
    }

    @MainActor
    func testAppLockEventsAreLogged() async throws {
        let start = Date().addingTimeInterval(-1)
        let folder = try makeScratchFolder()
        let (vault, _, _) = makeVault()
        let state = AppState(vault: vault, databasePath: folder.appendingPathComponent("Greenwick.sqlite").path,
                             screenshotsDirectory: folder.appendingPathComponent("Screenshots", isDirectory: true))
        _ = try await state.enableAppLock(password: password)
        state.lock()
        for _ in 0..<20 where state.database.isPersistent { await Task.yield() }
        _ = await state.unlock(password: "wrong-password")
        _ = await state.unlock(password: password)
        try await state.changeAppLockPassword(current: password, new: "another-pass-1")
        try await state.disableAppLock(password: "another-pass-1")
        state.shutdown()

        let messages = try appLockMessages(since: start)
        for expected in ["App Lock turned on", "App Lock: wrong password", "App Lock: unlocked",
                         "App Lock password changed", "App Lock turned off"] {
            XCTAssertTrue(messages.contains { $0.contains(expected) }, "Missing \"\(expected)\" in \(messages)")
        }
        XCTAssertFalse(messages.contains { $0.contains(password) || $0.contains("another-pass-1") })
    }
}
