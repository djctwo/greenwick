import CryptoKit
import SwiftUI
import GRDB
import os

/// Global app state injected via @Environment
///
/// Owns the journal's lifecycle: with App Lock on, nothing is decrypted until the password
/// (or the Touch ID / Mac password recovery) releases the key, and locking again closes the
/// journal and drops the key from memory.
@Observable
final class AppState {
    /// The one app-wide instance (one journal per process)
    nonisolated(unsafe) static let shared = AppState() // created and used on the main thread

    private(set) var database: DatabaseManager
    private(set) var tradeRepository: TradeRepository
    @ObservationIgnored let vault: AppLockVault
    @ObservationIgnored let databasePath: String
    @ObservationIgnored let screenshotsDirectory: URL
    /// The trade screenshots, sealed with the journal's key (`AppState+Screenshots.swift`)
    @ObservationIgnored let screenshots: ScreenshotManager
    /// Keys (raw) that some screenshot may still need after a key change couldn't re-seal
    /// every file: the next change or Turn Off first finishes that (`finishPendingScreenshots`).
    /// Cleared when Greenwick locks; the next unlock finds them in the Keychain again.
    @ObservationIgnored var pendingScreenshotKeys: [Data] = []
    /// The background sealing of plain screenshots from older versions (tests await it)
    @ObservationIgnored var legacyScreenshotSealing: Task<Int, Never>?
    /// Writes the sealed journal (tests inject a failing disk)
    @ObservationIgnored let journalWriter: JournalFileWriter
    /// Held while this process owns the data folder (`InstanceLock`)
    @ObservationIgnored private var instanceLock: InstanceLock?
    /// Test seams for the moments an `await` lets other main-actor work (e.g. a lock) run
    @ObservationIgnored var hooks = Hooks()
    static let logger = Logger(subsystem: "com.greenwick", category: "AppState")

    var selectedTab: SidebarTab = .journal
    var selectedDashboardCategory: DashboardViewModel.DashboardCategory = .overview
    var databaseError: String?
    var toast: ToastData?

    /// App is in an unrecoverable state — database failed even after recovery
    var isDatabaseFailed: Bool = false

    /// The lock screen is showing and the journal is closed
    var isLocked: Bool = false

    /// App Lock is turned on (a lock password exists). Set by the App Lock operations
    /// (`AppState+AppLock.swift`) only.
    var isAppLockEnabled: Bool = false

    /// The journal on disk is older than the last one this Mac saved (rollback): it stays
    /// closed until the owner confirms (`openOlderJournal`, or the lock password again)
    var olderJournal: DatabaseManager.OlderJournal?

    /// Another running copy of Greenwick has this data folder open: this one opens nothing
    /// and only offers to quit (`InstanceLock`)
    private(set) var isAnotherCopyRunning = false

    /// An App Lock key operation is running (unlock, Forgot Password, erase, turning the lock
    /// on or off, changing its password). They run one at a time (`performKeyOperation`).
    var isKeyOperationRunning = false
    /// A lock was asked for while a key operation ran: it locks when that finishes
    @ObservationIgnored var isLockRequested = false

    /// The journal whose final save failed when Greenwick locked (e.g. a full disk). Its
    /// changes exist nowhere else, so it stays decrypted in memory behind the lock screen and
    /// is put back (and saved again) at unlock; quitting asks first (`saveBeforeQuit`).
    @ObservationIgnored var heldJournal: DatabaseManager?

    /// At launch a lock item existed but couldn't be read (fail closed: the lock screen shows,
    /// even if App Lock is off): the lock screen says so right away
    var keychainUnreadableAtLaunch = false

    /// "Forgot password?" can use Touch ID / the Mac password (needs a signed build)
    var isRecoveryAvailable: Bool { vault.isRecoveryAvailable }

    /// Show a toast notification
    func showToast(_ style: ToastStyle, _ message: String) {
        toast = ToastData(style: style, message: message)
    }

    init(
        vault: AppLockVault = .live,
        databasePath: String = AppPaths.databaseURL.path,
        screenshotsDirectory: URL = AppPaths.screenshotsDirectory,
        journalWriter: JournalFileWriter = .secure,
        screenshotWriter: JournalFileWriter = .secure
    ) {
        self.vault = vault
        self.databasePath = databasePath
        self.screenshotsDirectory = screenshotsDirectory
        self.screenshots = ScreenshotManager(baseDir: screenshotsDirectory, writer: screenshotWriter)
        self.journalWriter = journalWriter
        let placeholder = Self.makePlaceholder()
        self.database = placeholder
        self.tradeRepository = TradeRepository(database: placeholder)

        // Before anything reads the Keychain or the journal: one copy per data folder
        switch InstanceLock.acquire(in: URL(fileURLWithPath: databasePath).deletingLastPathComponent()) {
        case .acquired(let lock):
            instanceLock = lock
        case .heldElsewhere:
            Self.logger.notice("Another copy of Greenwick has this journal open; opening nothing")
            isAnotherCopyRunning = true
            return
        case .unavailable:
            break
        }

        DatabaseEncryption.removeStrayTemporaryCopies()
        isAppLockEnabled = vault.isLockEnabled
        if isAppLockEnabled {
            // Decrypt nothing before the password: show the lock screen with the journal closed
            keychainUnreadableAtLaunch = vault.hasUnreadableLockItem
            secureLeftoverPlaintextWhileLocked()
            isLocked = true
        } else {
            openJournalWithPlainKey()
            screenshotsBecameReadable()
        }

        // Optional launch argument, e.g. `-startTab Dashboard` (not persisted)
        if let raw = UserDefaults.standard.string(forKey: "startTab"),
           let tab = SidebarTab(rawValue: raw) {
            self.selectedTab = tab
        }
    }

    // MARK: - Opening and closing the journal

    /// An encrypted journal exists on disk (so a missing key must never be replaced)
    var encryptedJournalExists: Bool {
        FileManager.default.fileExists(atPath: databasePath) && !DatabaseEncryption.fileIsPlaintext(at: databasePath)
    }

    func openJournalWithPlainKey() {
        do {
            let key = try vault.plainKey(createIfMissing: !encryptedJournalExists)
            openJournal(key: key)
        } catch {
            // Never generate a new key over an existing journal: that would make it unreadable
            Self.logger.error("Journal key unavailable: \(error.localizedDescription)")
            isDatabaseFailed = true
            databaseError = "Greenwick can't read your journal's encryption key from the Keychain, so it "
                + "left the journal untouched. If macOS asked about Keychain access, quit, relaunch and allow it."
        }
    }

    /// Decrypt and open the journal file with `key` (see `DatabaseManager.init(path:…)`)
    func openManager(key: SymmetricKey, acceptOlder: Bool = false) throws -> DatabaseManager {
        try DatabaseManager(path: databasePath, key: key, ledger: vault.ledger, acceptOlder: acceptOlder,
                            writer: journalWriter)
    }

    /// Open the journal with `key`. A file that can't be decrypted is set aside (still
    /// encrypted) and a new journal started, so nothing is ever deleted. Any other failure
    /// (the disk or the folder, not the file) leaves the file exactly where it is.
    @discardableResult
    func openJournal(key: SymmetricKey) -> Bool {
        do {
            install(try openManager(key: key))
            return true
        } catch let older as DatabaseManager.OlderJournal {
            // Not unreadable, just older: leave it exactly as it is and ask the owner
            holdOlderJournal(older)
            return false
        } catch let error where !DatabaseManager.isUnreadable(error) {
            reportOpenFailure(error)
            return false
        } catch {
            Self.logger.error("Opening the journal failed: \(error.localizedDescription)")
        }
        let aside = DatabaseEncryption.moveAside(databasePath, key: key)
        let keptAs = aside.map {
            " The old file was kept (still encrypted) next to it as \(URL(fileURLWithPath: $0).lastPathComponent)."
        } ?? ""
        do {
            install(try openManager(key: key))
            databaseError = "Greenwick couldn't read your journal and started a new one." + keptAs
                + (database.lastSaveError.map { " The new journal couldn't be saved yet (\($0))." } ?? "")
            return true
        } catch {
            Self.logger.critical("Journal unusable: \(error.localizedDescription)")
            isDatabaseFailed = true
            databaseError = "Greenwick cannot start due to a database error. Please restart the app." + keptAs
            return false
        }
    }

    /// Opening failed for a reason other than the file itself (e.g. it can't be read from
    /// disk): nothing was moved or changed
    func reportOpenFailure(_ error: Error) {
        Self.logger.error("Opening the journal failed; file left untouched: \(error.localizedDescription)")
        isDatabaseFailed = true
        databaseError = Self.openFailureMessage(error)
    }

    static func openFailureMessage(_ error: Error) -> String {
        "Greenwick couldn't open your journal (\(error.localizedDescription)). The file was left untouched. "
            + "Check that your Mac has free disk space and that the Greenwick folder can be read, then "
            + "quit and reopen Greenwick."
    }

    func install(_ manager: DatabaseManager) {
        database = manager
        tradeRepository = TradeRepository(database: manager)
        // Screenshots open with the journal's key only while unlocked (none while locked)
        screenshots.useKey(isLocked ? nil : manager.encryptionKey)
        // Older versions kept the prop firm account size and limits in the plaintext preferences
        PropFirmSettings.migrateFromPreferences(.standard, into: manager)
        // E.g. a full disk: the journal is open in memory, but saving it failed
        if let message = manager.lastSaveError { reportSaveFailure(message) }
    }

    private static func makePlaceholder() -> DatabaseManager {
        // An empty in-memory database: creating it can only fail if SQLite itself is unusable
        try! DatabaseManager(inMemory: true) // swiftlint:disable:this force_try
    }

    /// Sealing the journal to disk failed: say so (the "Database Issue" alert), since
    /// changes now exist only in memory until a later save works
    func reportSaveFailure(_ message: String?) {
        Self.logger.error("Journal save failed; changes are only in memory")
        databaseError = "Greenwick couldn't save your journal to disk"
            + (message.map { " (\($0))" } ?? "")
            + ". Your latest changes are only in memory. Free up disk space or check access to the "
            + "Greenwick folder. Greenwick keeps them and tries again with your next change, when you unlock, "
            + "and when you quit (it asks before quitting without them)."
    }

    /// Close the journal (final save) and drop its key from memory. If the final save fails,
    /// the journal is kept in memory instead (`heldJournal`) so nothing is lost; returns false.
    @discardableResult
    func closeJournal() -> Bool {
        guard database.isPersistent else { return true }
        let open = database
        install(Self.makePlaceholder())
        guard open.finishSaving() else {
            Self.logger.error("Final save failed; the journal stays in memory until a save works")
            heldJournal = open
            return false
        }
        open.close()
        return true
    }

    /// The journal kept by a failed final save, put back and saved again (unlock). The
    /// "Database Issue" alert shows if saving still fails.
    func reinstallHeldJournal(_ held: DatabaseManager) {
        heldJournal = nil
        try? held.persistNow() // a failure is reported by `install` (`lastSaveError`)
        install(held)
    }

    /// Quitting: if the open (or held) journal has changes that couldn't be saved, try once
    /// more. Returns why saving still fails (quitting would lose those changes), else nil.
    func saveBeforeQuit() -> String? {
        let journal = heldJournal ?? database
        guard journal.isOpen, journal.lastSaveError != nil else { return nil }
        do {
            try journal.persistNow()
            return nil
        } catch {
            return journal.lastSaveError ?? error.localizedDescription
        }
    }

    /// App is quitting: save and close (the owner already chose to quit, see
    /// `saveBeforeQuit`), then let another copy open the folder
    func shutdown() {
        closeJournal()
        heldJournal?.close()
        heldJournal = nil
        instanceLock?.release()
        instanceLock = nil
    }

    /// While locked with a wrapped key the key isn't available, so a plaintext journal left by
    /// an older version can only be encrypted after unlock. An install from before key
    /// wrapping still has its plain key: encrypt right away.
    private func secureLeftoverPlaintextWhileLocked() {
        guard DatabaseEncryption.fileIsPlaintext(at: databasePath) else { return }
        guard !vault.hasWrappedKey, let key = try? vault.plainKey(createIfMissing: true) else {
            Self.logger.warning("Unencrypted journal found while locked; it is encrypted at unlock")
            return
        }
        do {
            try DatabaseEncryption.encryptPlaintextFile(at: databasePath, key: key)
        } catch {
            Self.logger.error("Could not encrypt the leftover journal: \(error.localizedDescription)")
        }
    }
}

// MARK: - Test seams

extension AppState {
    /// Called at the points where an `await` lets other main-actor work run (in the app:
    /// nothing). Tests lock the app there to check that no key change or lock change goes
    /// wrong when a lock lands in between.
    struct Hooks {
        /// Unlock: runs while the password is being checked off the main thread
        var whileUnlocking: (@MainActor () async -> Void)?
        /// Key rotation: runs while step 1 (wrapping the new key) runs off the main thread
        var whileRotationBegins: (@MainActor () async -> Void)?
        /// Key rotation: step 1 (the new wrapped key) is stored, step 2 not started
        var afterRotationBegan: (@MainActor () async -> Void)?
        /// Turn Off App Lock: the password was checked, nothing changed yet
        var afterDisablePasswordCheck: (@MainActor () async -> Void)?
    }
}

// MARK: - Environment Key

extension EnvironmentValues {
    @Entry var appState: AppState = AppState.shared
}
