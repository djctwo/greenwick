import CryptoKit
import Foundation
import GRDB
import os

/// Writes the sealed journal after every committed transaction (on GRDB's writer queue,
/// so each save is a consistent snapshot and saves never interleave).
///
/// Every write carries the next generation (`JournalStamp`) in the file header and then
/// records it in the `JournalLedger`. The file is written first: if the app stops in
/// between, the file is one save ahead of the Keychain, which is accepted at the next
/// launch. A failed Keychain write is logged and the app keeps working.
///
/// Closing (`close(_:)`) makes the final save and marks the journal closed in one turn of the
/// writer queue: a change that reaches the queue later is refused (`checkOpen`), never
/// committed to memory only. If the final save fails the journal stays open (and keeps
/// saving after each change), so what exists only in memory is never thrown away silently.
final class JournalPersistence: @unchecked Sendable {
    private let path: String
    private let ledger: JournalLedger?
    private let writer: JournalFileWriter
    private let lock = NSLock()
    private var currentKey: Data
    private let epoch: Data
    private var generation: UInt64
    private var stamp: JournalStamp?
    private var cancellable: AnyDatabaseCancellable?
    private var error: String?
    private var isLedgerFailing = false
    private var isClosed = false
    private static let logger = Logger(subsystem: "com.greenwick", category: "Database")

    /// - Parameters:
    ///   - epoch: the line of saves this journal continues (`JournalStamp.epoch`)
    ///   - generation: the generation of the journal as opened; the first save writes
    ///     `generation + 1`
    init(path: String, keyData: Data, epoch: Data, generation: UInt64, ledger: JournalLedger?,
         writer: JournalFileWriter = .secure) {
        self.path = path
        self.writer = writer
        self.currentKey = keyData
        self.epoch = epoch
        self.generation = generation
        self.ledger = ledger
    }

    var keyData: Data { lock.withLock { currentKey } }

    /// Stamp of the last write (nil before the first)
    var lastStamp: JournalStamp? { lock.withLock { stamp } }

    var lastError: String? { lock.withLock { error } }

    /// False once `close(_:)` ran (the final save is done; nothing more is written)
    var isOpen: Bool { lock.withLock { !isClosed } }

    /// Throws `StorageError.closed` once the journal is closed. Call it inside the write
    /// that changes the journal (on the writer queue), so the check and the change can't be
    /// separated by the final save.
    func checkOpen() throws {
        guard isOpen else { throw DatabaseManager.StorageError.closed }
    }

    /// Re-seal with `newKey` (one write, a new generation) and use it from now on
    func rekey(_ db: Database, to newKey: Data) throws {
        try checkOpen()
        try write(DatabaseManager.serialize(db), key: newKey)
        lock.withLock { currentKey = newKey }
    }

    func start(on queue: DatabaseQueue) {
        let observation = DatabaseRegionObservation(tracking: .fullDatabase)
        let token = observation.start(in: queue, onError: { error in
            Self.logger.error("Save observation failed: \(error.localizedDescription)")
        }, onChange: { [weak self] db in
            guard let self else { return }
            do {
                try self.save(db)
            } catch {
                Self.logger.error("Saving the journal failed: \(error.localizedDescription)")
            }
        })
        lock.withLock { cancellable = token }
    }

    func stop() {
        lock.withLock {
            cancellable?.cancel()
            cancellable = nil
        }
    }

    /// Final save, then closed: on the writer queue, in the same turn. When the save throws
    /// the journal stays open.
    func close(_ db: Database) throws {
        try save(db)
        lock.withLock { isClosed = true }
    }

    /// Stop for good without saving (the owner chose to quit or erase anyway)
    func abandon() {
        lock.withLock { isClosed = true }
        stop()
    }

    func save(_ db: Database) throws {
        try checkOpen()
        do {
            try write(try DatabaseManager.serialize(db), key: keyData)
            lock.withLock { error = nil }
        } catch {
            let message = error.localizedDescription
            let isNew = lock.withLock {
                defer { self.error = message }
                return self.error == nil
            }
            // Tell the app once per failure streak: changes are only in memory until a save works
            if isNew {
                NotificationCenter.default.post(name: .journalSaveFailed, object: nil,
                                                userInfo: [DatabaseManager.saveErrorKey: message])
            }
            throw error
        }
    }

    /// Seal `plaintext` as the next generation, write it, then record it in the ledger.
    /// Called on the writer queue only, so generations never interleave.
    private func write(_ plaintext: Data, key: Data) throws {
        let next = lock.withLock { generation } + 1
        let newStamp = JournalStamp(epoch: epoch, generation: next, savedAt: Date())
        let fileHash = try DatabaseEncryption.writeJournal(plaintext, to: path, key: SymmetricKey(data: key),
                                                           stamp: newStamp, writer: writer)
        lock.withLock {
            generation = next
            stamp = newStamp
        }
        guard let ledger else { return }
        let isRecorded = ledger.record(JournalLedger.Entry(stamp: newStamp, fileHash: fileHash))
        let isNewFailure = lock.withLock {
            defer { isLedgerFailing = !isRecorded }
            return !isRecorded && !isLedgerFailing
        }
        if isNewFailure {
            // Nothing is lost: the journal file is saved. Rollback detection just lags until
            // a later Keychain write succeeds (a newer file than recorded is accepted).
            Self.logger.error("Journal saved, but its generation couldn't be recorded in the Keychain")
        }
    }
}

/// Writes the sealed journal bytes to disk. The app always uses `.secure`; tests inject
/// failures (for example a full disk) to check that nothing is set aside or lost.
struct JournalFileWriter: Sendable {
    let write: @Sendable (Data, URL) throws -> Void

    static let secure = JournalFileWriter { data, url in try SecureFileWriter.write(data, to: url) }
}

extension Notification.Name {
    /// Posted (from the database queue) when sealing the journal to disk fails. Until a
    /// later save succeeds, changes exist only in memory.
    static let journalSaveFailed = Notification.Name("GreenwickJournalSaveFailed")
}
