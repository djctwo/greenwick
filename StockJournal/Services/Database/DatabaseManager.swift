import CryptoKit
import Foundation
import GRDB
import os
import SQLite3

/// Owns the journal database.
///
/// The journal is opened **in memory**: the encrypted file is decrypted into RAM with
/// `sqlite3_deserialize`, and after every committed change the whole database is
/// serialized, sealed with AES-256-GCM and written back atomically. The plaintext journal
/// never touches the disk, so a crash, force quit or power loss leaves only the encrypted
/// file behind.
final class DatabaseManager: Sendable {
    let dbQueue: DatabaseQueue
    /// The encrypted journal file ("" for an in-memory database that is never saved)
    let databasePath: String
    private let persistence: JournalPersistence?
    private static let logger = Logger(subsystem: "com.greenwick", category: "Database")

    /// Open (or create) the encrypted journal at `path` with `key`.
    ///
    /// A plaintext SQLite file found at `path` (older version or unclean shutdown) is
    /// encrypted in place before anything else. A file that can't be decrypted throws
    /// and is left untouched.
    ///
    /// With a `ledger`, a file that isn't the last save this Mac made (or a later save of
    /// the same line) throws `OlderJournal` and is left untouched: an earlier generation, a
    /// copy from another line of saves (epoch), or the same generation with other content.
    /// With `acceptOlder` (the owner confirmed) it opens and a NEW line of saves starts,
    /// continuing after the highest generation seen: the counter never goes down, so files
    /// from the abandoned line are refused later. A file from before generations existed
    /// counts as generation 0. A missing file continues the recorded line.
    ///
    /// The save made while opening (it records the new generation) may fail, e.g. on a full
    /// disk: the journal then stays open in memory and `lastSaveError` says why. Nothing is
    /// set aside for that; only a file that can't be decrypted throws (`isUnreadable`).
    init(path: String, key: SymmetricKey, ledger: JournalLedger? = nil, acceptOlder: Bool = false,
         writer: JournalFileWriter = .secure) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)

        let lastSaved = ledger?.read()
        var plaintext: Data?
        var epoch = lastSaved?.stamp.epoch ?? JournalStamp.newEpoch()
        var generation = lastSaved?.stamp.generation ?? 0
        if FileManager.default.fileExists(atPath: path) {
            var stamp: JournalStamp?
            var fileHash = Data()
            if DatabaseEncryption.fileIsPlaintext(at: path) {
                plaintext = try DatabaseEncryption.encryptPlaintextFile(at: path, key: key)
            } else {
                let sealed = try Data(contentsOf: URL(fileURLWithPath: path))
                fileHash = JournalFormat.fingerprint(of: sealed)
                (plaintext, stamp) = try JournalFormat.open(sealed, key: key)
            }
            let verdict = JournalLedger.verdict(file: stamp, fileHash: fileHash, last: lastSaved)
            if verdict != .expected, let lastSaved {
                guard acceptOlder else {
                    throw OlderJournal(file: stamp, lastSaved: lastSaved.stamp, reason: verdict)
                }
                Self.logger.notice("Opening a journal that isn't the last one saved on this Mac (owner confirmed)")
                epoch = JournalStamp.newEpoch()
                generation = max(lastSaved.stamp.generation, stamp?.generation ?? 0)
            } else if let stamp {
                epoch = stamp.epoch
                generation = stamp.generation
            } else {
                epoch = JournalStamp.newEpoch()
                generation = 0
            }
            // Left over from an older version; their content is already in the main file
            DatabaseEncryption.removeSidecars(of: path)
        }

        let queue = try DatabaseQueue(configuration: Self.configuration())
        if let plaintext {
            try queue.writeWithoutTransaction { db in try Self.deserialize(plaintext, into: db) }
        }
        // Never `eraseDatabaseOnSchemaChange`, not even in Debug: a source build run from
        // Xcode can open a real journal written by a newer version and would erase it
        try Self.makeMigrator().migrate(queue)

        self.dbQueue = queue
        self.databasePath = path
        self.persistence = JournalPersistence(path: path, keyData: keyData, epoch: epoch, generation: generation,
                                              ledger: ledger, writer: writer)
        do {
            try persistNow()
        } catch {
            // Already reported (`lastSaveError`, `.journalSaveFailed`); the decrypted journal
            // stays open and the next change saves again
            Self.logger.error("Saving the opened journal failed; it stays open in memory")
        }
        persistence?.start(on: queue)
        Self.logger.info("Journal opened in memory")
    }

    /// In-memory database that is never written anywhere (tests, and the stand-in used
    /// while the app is locked)
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(path:key:) for the journal")
        let queue = try DatabaseQueue(configuration: Self.configuration())
        try Self.makeMigrator().migrate(queue)
        self.dbQueue = queue
        self.databasePath = ""
        self.persistence = nil
    }

    private static func configuration() -> GRDB.Configuration {
        var config = GRDB.Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG
        config.prepareDatabase { db in
            db.trace { Self.logger.debug("\($0)") }
        }
        #endif
        return config
    }

    /// The journal's key (to wrap it when App Lock is turned on). nil for in-memory databases.
    var encryptionKey: SymmetricKey? {
        persistence.map { SymmetricKey(data: $0.keyData) }
    }

    /// Re-seal the journal file with `key` (one atomic write) and use it from now on.
    /// Runs on the writer queue, so no save with the old key can follow it. Throws
    /// `StorageError.closed` for a closed or in-memory journal: a key rotation must never
    /// believe a file was re-sealed when it wasn't.
    func rekey(to key: SymmetricKey) throws {
        guard let persistence else { throw StorageError.closed }
        let raw = key.withUnsafeBytes { Data($0) }
        try dbQueue.writeWithoutTransaction { db in try persistence.rekey(db, to: raw) }
    }

    /// The journal file on disk decrypts with `key` (checked after a re-seal, before the old
    /// key is deleted)
    func fileOpens(with key: SymmetricKey) -> Bool {
        guard isPersistent, let sealed = try? Data(contentsOf: URL(fileURLWithPath: databasePath)) else {
            return false
        }
        return (try? JournalFormat.open(sealed, key: key)) != nil
    }

    var isPersistent: Bool { persistence != nil }

    /// A journal file that is open and still saving (false once closed, and for in-memory databases)
    var isOpen: Bool { persistence?.isOpen ?? false }

    /// Throws `StorageError.closed` once the journal is closed. Call it inside a write that
    /// runs off the main thread (e.g. a restore), so it can't land after the final save.
    func checkOpen() throws {
        try persistence?.checkOpen()
    }

    /// Whether `error` from opening a journal means the file itself can't be read with that
    /// key (wrong key, damaged or not a journal), as opposed to the disk or folder failing.
    /// Only such a file may be set aside; anything else leaves the file untouched.
    static func isUnreadable(_ error: Error) -> Bool {
        switch error {
        case DatabaseEncryption.EncryptionError.decryptionFailed, StorageError.notADatabase:
            return true
        case let error as DatabaseError:
            return error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB
        default:
            return false
        }
    }

    /// Stamp of the last save written to disk (nil for in-memory databases)
    var lastSavedStamp: JournalStamp? { persistence?.lastStamp }

    // MARK: - Serialization

    /// The whole database as SQLite file bytes (for backups)
    func serializedSnapshot() throws -> Data {
        try dbQueue.writeWithoutTransaction { db in try Self.serialize(db) }
    }

    static func serialize(_ db: Database) throws -> Data {
        guard let connection = db.sqliteConnection else { throw StorageError.closed }
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(connection, "main", &size, 0) else {
            throw StorageError.serializationFailed
        }
        defer { sqlite3_free(bytes) }
        return Data(bytes: bytes, count: Int(size))
    }

    /// Replace the "main" database of `db` with the SQLite file `bytes` (copied into
    /// SQLite-owned memory). A WAL-mode file is switched to rollback mode, as SQLite needs.
    static func deserialize(_ bytes: Data, into db: Database, readOnly: Bool = false) throws {
        guard DatabaseEncryption.isPlaintextSQLite(bytes), bytes.count >= 100 else {
            throw StorageError.notADatabase
        }
        guard let connection = db.sqliteConnection,
              let buffer = sqlite3_malloc64(sqlite3_uint64(bytes.count)) else {
            throw StorageError.serializationFailed
        }
        let pointer = buffer.assumingMemoryBound(to: UInt8.self)
        bytes.copyBytes(to: pointer, count: bytes.count)
        pointer[18] = 1 // file format write version: legacy (not WAL)
        pointer[19] = 1 // file format read version
        var flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
        if readOnly { flags |= UInt32(SQLITE_DESERIALIZE_READONLY) }
        // On failure SQLite frees the buffer itself (FREEONCLOSE)
        let rc = sqlite3_deserialize(connection, "main", pointer, sqlite3_int64(bytes.count),
                                     sqlite3_int64(bytes.count), flags)
        guard rc == SQLITE_OK else { throw StorageError.notADatabase }
        db.clearSchemaCache()
    }

    // MARK: - Saving

    /// Seal the current database and write it to `databasePath` (no-op when in memory only)
    func persistNow() throws {
        guard let persistence else { return }
        try dbQueue.writeWithoutTransaction { db in try persistence.save(db) }
    }

    /// Save one last time and stop saving, in one turn of the writer queue: a change that
    /// reaches the queue afterwards is refused (`checkOpen`), never left unsaved in memory.
    /// Returns false when the final save failed: the journal then stays open and keeps
    /// saving after each change, so its unsaved changes aren't lost.
    @discardableResult
    func finishSaving() -> Bool {
        guard let persistence, persistence.isOpen else { return true }
        do {
            try dbQueue.writeWithoutTransaction { db in try persistence.close(db) }
        } catch {
            Self.logger.error("Final save failed; the journal stays open: \(error.localizedDescription)")
            return false
        }
        persistence.stop()
        return true
    }

    /// Save one last time (unless `saving` is false) and close, even when that save fails:
    /// only for quitting or erasing, after the owner was told. Further use of this manager
    /// throws instead of crashing.
    func close(saving: Bool = true) {
        if !saving || !finishSaving() { persistence?.abandon() }
        do {
            try dbQueue.close()
        } catch {
            Self.logger.error("Closing the journal failed: \(error.localizedDescription)")
        }
    }

    /// Error from the most recent automatic save, if it failed
    var lastSaveError: String? { persistence?.lastError }

    /// `userInfo` key of `.journalSaveFailed`: the error message
    static let saveErrorKey = "message"

    /// The journal file is not the last one this Mac saved (`JournalLedger`): someone may
    /// have put an older copy in its place. It was not opened or changed.
    struct OlderJournal: LocalizedError, Equatable {
        /// The file's stamp (nil: sealed before stamps existed, generation 0)
        let file: JournalStamp?
        let lastSaved: JournalStamp
        /// `.older` (earlier save of the same line) or `.differentCopy`
        let reason: JournalLedger.Verdict

        var errorDescription: String? {
            let saved = lastSaved.savedAt.formatted(date: .abbreviated, time: .shortened)
            return reason == .older
                ? "This journal is older than the last one this Mac saved (saved \(saved))."
                : "This journal is not the last one this Mac saved (saved \(saved)); it may be an older copy."
        }
    }

    enum StorageError: LocalizedError {
        case closed
        case serializationFailed
        case notADatabase

        var errorDescription: String? {
            switch self {
            case .closed: "The journal is closed."
            case .serializationFailed: "The journal could not be prepared for saving."
            case .notADatabase: "The file is not a Greenwick database."
            }
        }
    }
}
