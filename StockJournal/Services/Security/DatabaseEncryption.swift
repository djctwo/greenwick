import CryptoKit
import Foundation
import GRDB
import os

/// AES-256-GCM encryption of the journal file at rest.
///
/// The journal is never written to disk in plaintext: `DatabaseManager` keeps the open
/// database in memory and writes only the sealed bytes (`JournalFormat`: a header with the
/// save counter, bound to `nonce | ciphertext | tag`).
/// The key comes from `AppLockVault`: a plain Keychain item when App Lock is off, or
/// wrapped with a key derived from the lock password when it is on.
///
/// This type also cleans up after older versions and crashes: a plaintext SQLite file
/// where the encrypted one is expected (an older Greenwick decrypted it in place) is
/// encrypted again at once, and stray plaintext copies are removed.
enum DatabaseEncryption {
    private static let logger = Logger(subsystem: "com.greenwick", category: "DatabaseEncryption")

    /// SQLite file magic header: "SQLite format 3\0"
    static let sqliteMagic = Data([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    ])

    /// Files next to a SQLite database that hold pieces of it in plaintext
    static let sidecarSuffixes = ["-wal", "-shm", "-journal"]

    // MARK: - Seal / open

    static func isPlaintextSQLite(_ data: Data) -> Bool {
        data.count >= sqliteMagic.count && data.prefix(sqliteMagic.count) == sqliteMagic
    }

    /// True if a plaintext SQLite file sits at `path`
    static func fileIsPlaintext(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: sqliteMagic.count)) ?? Data()
        return head == sqliteMagic
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    static func open(_ ciphertext: Data, key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    /// Seal `plaintext` and write it to `path` atomically, readable by the owner only
    /// (`SecureFileWriter`: 0600 from creation, no path-based chmod, symlinks never followed)
    static func writeSealed(_ plaintext: Data, to path: String, key: SymmetricKey) throws {
        try SecureFileWriter.write(try seal(plaintext, key: key), to: URL(fileURLWithPath: path))
    }

    /// Seal the journal with its save `stamp` in the header (`JournalFormat`) and write it
    /// to `path` the same way as `writeSealed` (owner-only, atomic, never through a link).
    /// Returns the written file's `JournalFormat.fingerprint`.
    @discardableResult
    static func writeJournal(_ plaintext: Data, to path: String, key: SymmetricKey, stamp: JournalStamp,
                             writer: JournalFileWriter = .secure) throws -> Data {
        let sealed = try JournalFormat.seal(plaintext, key: key, stamp: stamp)
        try writer.write(sealed, URL(fileURLWithPath: path))
        return JournalFormat.fingerprint(of: sealed)
    }

    // MARK: - Recovery from older versions and crashes

    /// A plaintext SQLite file at `path` (an older Greenwick decrypted the journal in place
    /// and didn't get to encrypt it again): fold its WAL in, encrypt it in place with `key`,
    /// and remove the plaintext sidecar files. Returns the plaintext bytes.
    @discardableResult
    static func encryptPlaintextFile(at path: String, key: SymmetricKey) throws -> Data {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path + "-wal") {
            // Changes may still be in the WAL only: checkpoint them into the main file
            var config = GRDB.Configuration()
            config.label = "greenwick.recovery"
            let queue = try DatabaseQueue(path: path, configuration: config)
            try queue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            try queue.close()
        }
        let plaintext = try Data(contentsOf: URL(fileURLWithPath: path))
        guard isPlaintextSQLite(plaintext) else { return try JournalFormat.open(plaintext, key: key).plaintext }
        try writeSealed(plaintext, to: path, key: key)
        removeSidecars(of: path)
        logger.warning("Found an unencrypted journal (older version or unclean shutdown); encrypted it again")
        return plaintext
    }

    static func removeSidecars(of path: String) {
        for suffix in sidecarSuffixes where FileManager.default.fileExists(atPath: path + suffix) {
            do {
                try FileManager.default.removeItem(atPath: path + suffix)
            } catch {
                logger.error("Could not remove \(suffix, privacy: .public) file: \(error.localizedDescription)")
            }
        }
    }

    /// Temporary plaintext copies older versions wrote while exporting or restoring a backup
    /// (deleted when they finished, but left behind by a crash)
    static func removeStrayTemporaryCopies(in directory: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".sqlite")
            && (name.hasPrefix("greenwick-backup-") || name.hasPrefix("greenwick-restore-")) {
            let path = directory.appendingPathComponent(name).path
            try? FileManager.default.removeItem(atPath: path)
            removeSidecars(of: path)
        }
    }

    /// Move an unreadable journal aside instead of deleting it. A plaintext file is sealed
    /// with `key` first (when there is one) so no readable copy is left behind.
    @discardableResult
    static func moveAside(_ path: String, key: SymmetricKey?) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = "\(path).unreadable-\(stamp)"
        do {
            if fileIsPlaintext(at: path) {
                let plaintext = try Data(contentsOf: URL(fileURLWithPath: path))
                if let key {
                    try writeSealed(plaintext, to: aside, key: key)
                    try FileManager.default.removeItem(atPath: path)
                } else {
                    // No key to protect it with: don't keep a plaintext copy
                    try FileManager.default.removeItem(atPath: path)
                    removeSidecars(of: path)
                    return nil
                }
            } else {
                try FileManager.default.moveItem(atPath: path, toPath: aside)
            }
            removeSidecars(of: path)
            logger.warning("Moved an unreadable journal aside")
            return aside
        } catch {
            logger.error("Could not move the unreadable journal aside: \(error.localizedDescription)")
            return nil
        }
    }

    /// Every journal-related file in `directory` (database, sidecars, set-aside copies)
    static func journalFiles(in directory: URL, databaseName: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(databaseName) }.map { directory.appendingPathComponent($0) }
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case decryptionFailed
        case encryptionFailed

        var errorDescription: String? {
            switch self {
            case .decryptionFailed:
                "Failed to decrypt the database. The encryption key may have changed."
            case .encryptionFailed:
                "Failed to encrypt the database."
            }
        }
    }
}
