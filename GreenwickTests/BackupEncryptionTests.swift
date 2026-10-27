import CryptoKit
import XCTest
@testable import Greenwick

/// Password-protected backups: the file format (PBKDF2-SHA256 600,000 rounds, AES-256-GCM
/// with the header as associated data), its limits, and older "SJNL" files.
final class BackupEncryptionTests: XCTestCase {
    private let password = "backup-pass-1"

    /// A journal holding one trade of the user's own ("MINE")
    private func makeLiveJournal() throws -> DatabaseManager {
        let live = try DatabaseManager(inMemory: true)
        var mine = sampleTrades()[0]
        mine.ticket = 42
        mine.symbol = "MINE"
        mine.isSample = false
        XCTAssertEqual(try TradeRepository(database: live).bulkInsert([mine]), 1)
        return live
    }

    private func symbols(_ db: DatabaseManager) throws -> [String] {
        try TradeRepository(database: db).fetchAll().map(\.symbol)
    }

    private func rounds(in sealed: Data) -> UInt32 {
        [UInt8](sealed)[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func testProtectedBackupRoundTripsWithTheCurrentFormat() throws {
        let plain = try backupBytes(with: sampleTrades())
        let sealed = try BackupEncryption.encrypt(plain, password: password)

        XCTAssertEqual(sealed.prefix(4), Data("GWBK".utf8))
        XCTAssertEqual([UInt8](sealed)[4], 2, "Format version")
        XCTAssertEqual(rounds(in: sealed), 600_000)
        XCTAssertEqual([UInt8](sealed)[9], 16, "Salt length")
        XCTAssertFalse(DatabaseEncryption.isPlaintextSQLite(sealed))
        XCTAssertNil(sealed.range(of: Data("SQLite format 3".utf8)))
        XCTAssertNil(sealed.range(of: Data("NVDA".utf8)), "No trade text in the file")
        XCTAssertEqual(BackupEncryption.format(of: sealed), .protected)
        XCTAssertEqual(try BackupEncryption.decrypt(sealed, password: password), plain)

        let again = try BackupEncryption.encrypt(plain, password: password)
        XCTAssertNotEqual(sealed.subdata(in: 10..<26), again.subdata(in: 10..<26), "Fresh salt per backup")

        let live = try makeLiveJournal()
        try BackupService.restore(from: sealed, password: password, into: live)
        XCTAssertEqual(try TradeRepository(database: live).count(), 30)
    }

    func testWrongPasswordLeavesTheJournalUntouched() throws {
        let sealed = try BackupEncryption.encrypt(try backupBytes(with: sampleTrades()), password: password)
        let live = try makeLiveJournal()
        XCTAssertThrowsError(try BackupService.restore(from: sealed, password: "not-the-password", into: live)) {
            XCTAssertEqual($0 as? BackupEncryption.Failure, .wrongPassword)
            XCTAssertTrue($0.localizedDescription.contains("Wrong password"))
            XCTAssertTrue($0.localizedDescription.contains("journal was not changed"))
        }
        XCTAssertThrowsError(try BackupService.restore(from: sealed, password: nil, into: live)) {
            XCTAssertEqual($0 as? BackupEncryption.Failure, .passwordRequired)
        }
        XCTAssertEqual(try symbols(live), ["MINE"])
    }

    /// The header is the AES-GCM associated data: any change to it (salt, round count,
    /// version) or to the ciphertext makes the file fail to open, and nothing is restored
    func testTamperedHeaderOrBodyIsRefused() throws {
        let sealed = try BackupEncryption.encrypt(try backupBytes(with: sampleTrades()), password: password)
        let live = try makeLiveJournal()
        let tamperings: [(String, Int, BackupEncryption.Failure)] = [
            ("salt", 12, .wrongPassword),
            ("round count", 8, .wrongPassword),          // 600,000 → 600,001
            ("version", 4, .unsupportedVersion),
            ("salt length", 9, .damaged),
            ("ciphertext", sealed.count - 20, .wrongPassword),
        ]
        for (part, index, expected) in tamperings {
            var bytes = [UInt8](sealed)
            bytes[index] ^= 0x01
            XCTAssertThrowsError(try BackupService.restore(from: Data(bytes), password: password, into: live), part) {
                XCTAssertEqual($0 as? BackupEncryption.Failure, expected, part)
            }
        }
        XCTAssertThrowsError(try BackupEncryption.decrypt(sealed.prefix(40), password: password)) {
            XCTAssertEqual($0 as? BackupEncryption.Failure, .damaged, "Truncated")
        }
        XCTAssertEqual(try symbols(live), ["MINE"])
    }

    /// A crafted file asking for billions of PBKDF2 rounds would hang the restore: refused
    /// before any key derivation
    func testAbsurdRoundCountsAreRefusedBeforeDerivingAKey() throws {
        let sealed = try BackupEncryption.encrypt(try backupBytes(with: sampleTrades()), password: password)
        for rounds: UInt32 in [0, 10_000_001, 4_000_000_000] {
            var bytes = [UInt8](sealed)
            bytes.replaceSubrange(5..<9, with: withUnsafeBytes(of: rounds.bigEndian) { Array($0) })
            let start = Date()
            XCTAssertThrowsError(try BackupEncryption.decrypt(Data(bytes), password: password)) {
                XCTAssertEqual($0 as? BackupEncryption.Failure, .damaged, "\(rounds) rounds")
            }
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5, "\(rounds) rounds must not be derived")
        }
        XCTAssertEqual(BackupEncryption.maximumIterations, 10_000_000)
    }

    /// Older versions wrote "SJNL" | salt | sealed box with PBKDF2 100,000 rounds and no
    /// associated data. Such backups must still restore (built here byte by byte, the way
    /// the old code did, so the test doesn't depend on the new code's helpers).
    func testOlderProtectedBackupsStillRestore() throws {
        let plain = try backupBytes(with: sampleTrades())
        let salt = Data((0..<16).map { UInt8($0 * 7 + 1) })
        let raw = try XCTUnwrap(KeyDerivation.deriveKey(password: "old-pw", salt: salt, iterations: 100_000))
        let box = try XCTUnwrap(try AES.GCM.seal(plain, using: SymmetricKey(data: raw)).combined)
        let legacy = Data("SJNL".utf8) + salt + box
        XCTAssertEqual(BackupEncryption.format(of: legacy), .legacyProtected)
        XCTAssertTrue(BackupEncryption.isProtected(legacy))

        let live = try makeLiveJournal()
        XCTAssertThrowsError(try BackupService.restore(from: legacy, password: "wrong-pw", into: live)) {
            XCTAssertEqual($0 as? BackupEncryption.Failure, .wrongPassword)
        }
        XCTAssertEqual(try symbols(live), ["MINE"])
        try BackupService.restore(from: legacy, password: "old-pw", into: live)
        XCTAssertEqual(try TradeRepository(database: live).count(), 30)
    }

    /// New protected backups never use the old format, and follow the App Lock password rule
    func testNewBackupsUseTheNewFormatAndTheAppLockStrengthRule() throws {
        let folder = try makeScratchFolder()
        let destination = folder.appendingPathComponent("b.sjbackup-enc")
        try BackupService.writeBackup(try backupBytes(with: sampleTrades()), to: destination, password: password)
        let written = try Data(contentsOf: destination)
        XCTAssertEqual(written.prefix(4), Data("GWBK".utf8))
        XCTAssertEqual(rounds(in: written), 600_000)
        XCTAssertThrowsError(try BackupEncryption.encrypt(Data("x".utf8), password: "short")) {
            XCTAssertEqual($0 as? AppLockVault.VaultError, .passwordTooShort)
        }
    }

    func testPlainBackupsAreRecognisedAsNotProtected() throws {
        let plain = try backupBytes(with: sampleTrades())
        XCTAssertEqual(BackupEncryption.format(of: plain), .plain)
        XCTAssertThrowsError(try BackupEncryption.decrypt(plain, password: password)) {
            XCTAssertEqual($0 as? BackupEncryption.Failure, .notProtected)
        }
    }
}
