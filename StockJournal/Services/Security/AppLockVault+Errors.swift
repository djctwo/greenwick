import Foundation

extension AppLockVault {
    // MARK: Errors

    enum VaultError: LocalizedError, Equatable {
        case wrongPassword
        case passwordTooShort
        case keyUnavailable
        case storeFailed
        case notLocked
        case recoveryUnavailable
        case ownerNotConfirmed
        case eraseNotConfirmed
        /// The journal closed (e.g. quitting) while the change waited for the password check:
        /// nothing changed
        case lockedMeanwhile
        /// The Touch ID / Mac password recovery copy holds a key that no longer opens the
        /// journal (a password change was interrupted): only erasing is left without the password
        case recoveryKeyOutdated
        /// Too many wrong passwords: try again after this many seconds
        case tooManyAttempts(seconds: Int)
        /// A lock item exists but the Keychain wouldn't return it (not "not found"): stay locked
        case keychainUnreadable
        /// Another App Lock step (unlock, Forgot Password, a password change…) is still running
        case busy
        /// Erase couldn't delete the journal file, so it stopped before deleting any key
        case journalNotDeleted
        /// An earlier key change couldn't re-encrypt every screenshot yet, and they still
        /// can't be: their older key must stay, so nothing was changed
        case screenshotsPending

        var errorDescription: String? {
            switch self {
            case .wrongPassword: "Incorrect password."
            case .passwordTooShort: "Password must be at least \(AppLockVault.minimumPasswordLength) characters."
            case .keyUnavailable: "Greenwick can't read the journal's encryption key from your Keychain."
            case .storeFailed: "Greenwick couldn't save to your Keychain. Nothing was changed."
            case .notLocked: "App lock is not turned on."
            case .recoveryUnavailable: "Touch ID / Mac password recovery isn't available for this copy of Greenwick."
            case .ownerNotConfirmed: "Mac password or Touch ID not confirmed. App lock unchanged."
            case .eraseNotConfirmed: "Mac password or Touch ID not confirmed. Nothing was erased."
            case .lockedMeanwhile: "Greenwick locked before the change was made. Nothing was changed."
            case .recoveryKeyOutdated:
                "The Touch ID / Mac password recovery key no longer opens this journal (a password change "
                    + "was interrupted). Unlock with your current password, or erase all local data and start fresh."
            case .tooManyAttempts(let seconds): UnlockThrottle.waitMessage(seconds: seconds)
            case .keychainUnreadable:
                "Greenwick can't read App Lock from your Keychain right now, so the journal stays locked. If macOS "
                    + "asked about Keychain access, allow it; otherwise quit and reopen Greenwick."
            case .busy: "Greenwick is still finishing another App Lock step. Try again in a moment."
            case .journalNotDeleted:
                "Greenwick couldn't delete the journal file, so nothing was erased and your keys were kept. Check "
                    + "that the Greenwick folder can be changed (and that the file isn't marked Locked in Finder), "
                    + "then try again."
            case .screenshotsPending:
                "Greenwick couldn't finish re-encrypting your screenshots after the last password change, so "
                    + "nothing was changed (their previous key must stay until they are). Check that the Greenwick "
                    + "folder can be changed and the disk isn't full, then try again."
            }
        }
    }
}
