import Foundation
import os

/// "Back Up Journal" and "Restore Backup" in Settings.
///
/// Backing up offers "Protect this backup with a password" (on by default when App Lock is
/// on). Restoring looks at the chosen file: a password-protected backup opens a sheet that
/// asks for its password, then goes through the same validation as a plain backup. A wrong
/// password leaves the journal untouched and says so in the sheet.
@Observable
@MainActor
final class BackupFlowModel {
    enum Sheet: String, Identifiable {
        /// Backup options: password protection on/off, password + confirmation
        case export
        /// The chosen backup is password-protected: ask for its password
        case restorePassword
        var id: String { rawValue }
    }

    var sheet: Sheet?
    var protectWithPassword = false
    var password = ""
    var confirmation = ""
    var error: String?
    private(set) var isWorking = false
    /// Called after a successful restore (e.g. to refresh the trade count)
    @ObservationIgnored var onRestored: (() -> Void)?

    @ObservationIgnored private var pendingRestore: Data?
    @ObservationIgnored private let appState: AppState
    private nonisolated static let logger = Logger(subsystem: "com.greenwick", category: "Backup")

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Back up

    /// Open the backup options. Password protection starts on when App Lock is on.
    func beginExport() {
        clearFields()
        protectWithPassword = appState.isAppLockEnabled
        sheet = .export
    }

    /// The password to protect the backup with (nil = no password), or a message saying
    /// what is wrong with what was typed. Same strength rule as the App Lock password.
    func exportPassword() throws -> String? {
        guard protectWithPassword else { return nil }
        guard !password.isEmpty else { throw InputError.empty }
        guard password == confirmation else { throw InputError.mismatch }
        try AppLockVault.checkStrength(password)
        return password
    }

    /// Check the options, ask where to save, then write the backup
    func export() async {
        let chosenPassword: String?
        do {
            chosenPassword = try exportPassword()
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard let destination = BackupService.chooseBackupDestination(isProtected: chosenPassword != nil),
              !appState.isLocked else {
            return // cancelled, or the app locked while the panel was open
        }
        do {
            try await writeExport(to: destination, password: chosenPassword)
            appState.showToast(.success, chosenPassword == nil
                ? "Backup saved to \(destination.lastPathComponent) (not password-protected)"
                : "Password-protected backup saved to \(destination.lastPathComponent)")
            close()
        } catch {
            self.error = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Snapshot the journal and write it to `destination` (PBKDF2 runs off the main thread)
    func writeExport(to destination: URL, password: String?) async throws {
        guard !appState.isLocked else { throw DatabaseManager.StorageError.closed }
        isWorking = true
        defer { isWorking = false }
        let database = appState.database
        try await Task.detached(priority: .userInitiated) {
            try BackupService.exportBackup(from: database, to: destination, password: password)
        }.value
    }

    // MARK: - Restore

    /// Ask for a backup file, then restore it (asking for its password first if it has one)
    func beginRestore() async {
        do {
            guard let data = try BackupService.chooseBackupFile(), !appState.isLocked else { return }
            await receiveRestoreFile(data)
        } catch {
            appState.showToast(.error, "Restore failed: \(error.localizedDescription)")
        }
    }

    /// A backup file was chosen: a protected one waits for its password, a plain one is
    /// restored right away
    func receiveRestoreFile(_ data: Data) async {
        guard BackupEncryption.isProtected(data) else {
            await restore(data, password: nil)
            return
        }
        clearFields()
        pendingRestore = data
        sheet = .restorePassword
    }

    /// Restore the pending protected backup with the password typed in the sheet
    func submitRestorePassword() async {
        guard let data = pendingRestore, !isWorking else { return }
        guard !password.isEmpty else {
            error = BackupEncryption.Failure.passwordRequired.localizedDescription
            return
        }
        await restore(data, password: password)
    }

    private func restore(_ data: Data, password: String?) async {
        // Locked meanwhile: the journal is closed (only the empty stand-in is open)
        guard !appState.isLocked else { return close() }
        isWorking = true
        defer { isWorking = false }
        let database = appState.database
        do {
            try await Task.detached(priority: .userInitiated) {
                try BackupService.restore(from: data, password: password, into: database)
            }.value
            close()
            appState.showToast(.success, "Backup restored")
            onRestored?()
        } catch {
            Self.logger.notice("Backup restore refused: \(error.localizedDescription, privacy: .public)")
            if sheet == .restorePassword {
                self.password = ""
                self.error = error.localizedDescription
            } else {
                appState.showToast(.error, "Restore failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sheet

    func close() {
        clearFields()
        pendingRestore = nil
        sheet = nil
    }

    private func clearFields() {
        password = ""
        confirmation = ""
        error = nil
    }

    enum InputError: LocalizedError, Equatable {
        case empty
        case mismatch

        var errorDescription: String? {
            switch self {
            case .empty: "Enter a password, or turn off password protection."
            case .mismatch: "Passwords do not match."
            }
        }
    }
}
