import AppKit
import Foundation
import GRDB
import os
import UniformTypeIdentifiers

/// Handles database backup and restore for user data protection
enum BackupService {
    private static let logger = Logger(subsystem: "com.greenwick", category: "Backup")

    /// File extension of a password-protected backup (`BackupEncryption`)
    static let protectedExtension = "sjbackup-enc"
    /// File extension of a backup without a password (a plain SQLite copy of the journal)
    static let plainExtension = "sjbackup"

    /// Ask where to save a backup. Returns nil if the user cancelled.
    @MainActor
    static func chooseBackupDestination(isProtected: Bool) -> URL? {
        let panel = NSSavePanel()
        let ext = isProtected ? protectedExtension : plainExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = "Greenwick_Backup_\(Date().formatted(.dateTime.year().month().day())).\(ext)"
        panel.message = isProtected
            ? "Choose where to save your password-protected Greenwick backup"
            : "Choose where to save your Greenwick backup (not password-protected)"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Write a backup of `database` to `destination`: a consistent snapshot of the in-memory
    /// journal (no temporary plaintext file), sealed with `password` when one is given.
    static func exportBackup(from database: DatabaseManager, to destination: URL, password: String?) throws {
        try writeBackup(try database.serializedSnapshot(), to: destination, password: password)
    }

    /// Write backup bytes to `destination` (sealed with `password` when one is given),
    /// owner-only via `SecureFileWriter`. The save panel already confirmed overwriting.
    static func writeBackup(_ dbData: Data, to destination: URL, password: String?) throws {
        if let password, !password.isEmpty {
            try SecureFileWriter.write(try BackupEncryption.encrypt(dbData, password: password), to: destination)
            logger.debug("Password-protected backup saved")
        } else {
            // A complete readable copy of the journal: owner-only, never through a link
            try SecureFileWriter.write(dbData, to: destination)
            logger.debug("Database backup saved")
        }
    }

    /// Ask for a backup file and read it (size-checked). Returns nil if the user cancelled.
    /// Whether it needs a password is decided from its content (`BackupEncryption.format`).
    @MainActor
    static func chooseBackupFile() throws -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: plainExtension) ?? .data,
            UTType(filenameExtension: protectedExtension) ?? .data,
        ]
        panel.message = "Select a Greenwick backup file to restore"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return nil }

        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        guard size <= BackupValidator.maxBackupSize else { throw BackupValidator.ValidationError.tooLarge }
        return try Data(contentsOf: source)
    }

    /// Restore backup file bytes (plain or password-protected) into `database`.
    /// The backup is decrypted and validated in memory first; the journal changes only if
    /// both succeed (a wrong password leaves it untouched).
    static func restore(from sourceData: Data, password: String?, into database: DatabaseManager) throws {
        let restoredData: Data
        if BackupEncryption.isProtected(sourceData) {
            guard let password, !password.isEmpty else { throw BackupEncryption.Failure.passwordRequired }
            restoredData = try BackupEncryption.decrypt(sourceData, password: password)
        } else {
            restoredData = sourceData
        }

        let contents: BackupValidator.Contents
        do {
            contents = try BackupValidator.validatedContents(from: restoredData)
        } catch let error as BackupValidator.ValidationError {
            throw error
        } catch {
            throw BackupError.invalidBackupFile
        }
        // Only validated values are written, into the journal's own tables (created by the
        // app's migrator): nothing of the backup's structure reaches the journal. One
        // transaction: a failure leaves the journal as it was. Saved (encrypted) on commit.
        // The journal may have been closed (the app locked) while the backup was checked:
        // `checkOpen` runs on the writer queue, so the rows either go in before the final
        // save or not at all.
        try database.dbQueue.write { db in
            try database.checkOpen()
            try db.execute(sql: "DELETE FROM trades")
            try db.execute(sql: "DELETE FROM strategy_checkpoints")
            try db.execute(sql: "DELETE FROM settings")
            for trade in contents.trades {
                var row = trade
                try row.insert(db)
            }
            for checkpoint in contents.checkpoints {
                var row = checkpoint
                try row.insert(db)
            }
            for (key, value) in contents.settings {
                try db.execute(sql: "INSERT INTO settings (key, value) VALUES (?, ?)", arguments: [key, value])
            }
        }
        logger.debug("Database restored from backup")
    }

    /// Get the database file size
    static func databaseSize(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case invalidBackupFile

        var errorDescription: String? {
            switch self {
            case .invalidBackupFile: "The selected file is not a valid Greenwick backup."
            }
        }
    }
}
