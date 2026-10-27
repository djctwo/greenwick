import CryptoKit
import Foundation

/// Trade screenshots follow the journal: sealed with its key, readable only while unlocked,
/// and moved to the new key by every key rotation before an old key may be deleted
/// (`ScreenshotManager`).
extension AppState {
    /// The journal is open and Greenwick unlocked: screenshots use the journal's key, and
    /// plain image files left by older versions are sealed in the background.
    func screenshotsBecameReadable() {
        guard !isLocked, database.isOpen, let key = database.encryptionKey else {
            screenshots.useKey(nil)
            return
        }
        screenshots.useKey(key)
        let screenshots = self.screenshots
        legacyScreenshotSealing = Task.detached(priority: .utility) { screenshots.sealLegacyFiles() }
    }

    /// Re-seal every screenshot that opens with one of `olds` with `new` (off the main
    /// thread). Returns what may still need an old key; empty means none does.
    @MainActor
    func resealScreenshots(from olds: [SymmetricKey], to new: SymmetricKey) async -> [URL] {
        guard !olds.isEmpty else { return [] }
        let oldRaw = olds.map(AppLockVault.raw)
        let newRaw = AppLockVault.raw(new)
        let screenshots = self.screenshots
        return await Task.detached(priority: .userInitiated) {
            screenshots.reseal(from: oldRaw.map { SymmetricKey(data: $0) }, to: SymmetricKey(data: newRaw))
        }.value
    }

    /// Before the key changes again or App Lock is turned off: an earlier key change left
    /// screenshots that still need an older key (kept in the Keychain until they don't).
    /// Re-seal them with `current` now, or throw `screenshotsPending` and change nothing, so
    /// that older key is never dropped while a screenshot needs it.
    @MainActor
    func finishPendingScreenshots(to current: SymmetricKey) async throws {
        guard !pendingScreenshotKeys.isEmpty else { return }
        let olds = pendingScreenshotKeys.map { SymmetricKey(data: $0) }
        guard await resealScreenshots(from: olds, to: current).isEmpty else {
            Self.logger.error("Screenshots still need an older key; the key change was refused")
            throw AppLockVault.VaultError.screenshotsPending
        }
        pendingScreenshotKeys = []
    }
}
