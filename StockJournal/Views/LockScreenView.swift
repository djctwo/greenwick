import SwiftUI

/// Full-screen lock gate — shown on launch when app lock is enabled. The journal is still
/// encrypted and closed while this shows; the password unwraps its key.
struct LockScreenView: View {
    @Environment(\.appState) private var appState
    @State private var password = ""
    @State private var error: String?
    @State private var isUnlocking = false
    @State private var showResetConfirmation = false
    @State private var showEraseConfirmation = false
    /// The recovery key no longer opens the journal: erasing is the only way without the password
    @State private var isRecoveryOutdated = false
    @FocusState private var isFocused: Bool

    /// Wrong-password count and lockout, shared with Settings (kept in the Keychain)
    private var throttle: UnlockThrottle { appState.vault.throttle }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.kpiValue)
                .foregroundStyle(Color.textSecondary)

            Text("Greenwick is Locked")
                .font(.kpiValueSecondary)
                .fontWeight(.bold)

            if let older = appState.olderJournal {
                VStack(spacing: 8) {
                    Text(older.question)
                        .font(.bodyText)
                        .accessibilityIdentifier("olderJournal.question")
                    Text(older.fileDetail + " Enter your password again to open it.")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Enter your password to unlock")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
                    .onSubmit { unlock() }
                    .disabled(isLockedOut || isBusy)

                HStack(spacing: 12) {
                    if appState.olderJournal != nil {
                        Button("Cancel") {
                            appState.dismissOlderJournal()
                            error = nil
                        }
                        .accessibilityIdentifier("olderJournal.cancel")
                    }
                    Button(appState.olderJournal == nil ? "Unlock" : "Open Anyway") { unlock() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty || isLockedOut || isBusy)
                }

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error {
                    Text(error)
                        .font(.smallText)
                        .foregroundStyle(Color.semanticRed)
                }
            }

            Spacer()

            Button("Forgot Password?") {
                if appState.isRecoveryAvailable && !isRecoveryOutdated {
                    showResetConfirmation = true
                } else {
                    showEraseConfirmation = true
                }
            }
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            // Never while an unlock (or another App Lock step) is still running
            .disabled(isBusy)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
        .onAppear {
            isFocused = true
            if appState.keychainUnreadableAtLaunch {
                // Fail closed (even with App Lock off): say why at once, before any password
                error = AppLockVault.VaultError.keychainUnreadable.localizedDescription
            }
            checkLockoutStatus()
        }
        .alert("Reset App Lock?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Lock", role: .destructive) {
                Task { await confirmMacOwnerThenReset() }
            }
        } message: {
            Text("To remove the app lock, confirm with your Mac login password or Touch ID. Your trading data stays intact.")
        }
        .alert("Erase Greenwick Data?", isPresented: $showEraseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Erase All Local Data", role: .destructive) {
                Task { await confirmMacOwnerThenErase() }
            }
        } message: {
            Text(eraseExplanation)
        }
    }

    private var eraseExplanation: String {
        let why = isRecoveryOutdated
            ? "The Touch ID / Mac password recovery key no longer opens your journal (a password change was "
                + "interrupted), so only your current app lock password can."
            : "Your journal is encrypted with your app lock password, and this copy of Greenwick can't use "
                + "Touch ID or your Mac password to recover it."
        return why + " Without the password the journal can't be opened. You can erase all local data (journal, "
            + "screenshots and keys) and start fresh after confirming with your Mac login password or Touch ID, "
            + "or cancel and keep trying."
    }

    /// An unlock, recovery or erase is running: the other buttons wait for it
    private var isBusy: Bool { isUnlocking || appState.isKeyOperationRunning }

    // MARK: - Brute Force Protection

    /// Whether no password may be checked now (a wait, or the count can't be read)
    private var isLockedOut: Bool { throttle.refusal != nil }

    private func checkLockoutStatus() {
        if let refusal = throttle.refusal {
            error = refusal.localizedDescription
        }
    }

    private func recordFailedAttempt() {
        do {
            let (attempts, lockout) = try throttle.recordFailure()
            error = lockout > 0
                ? UnlockThrottle.waitMessage(seconds: lockout)
                : "Incorrect password (\(attempts)/\(UnlockThrottle.freeAttempts))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearFailedAttempts() {
        throttle.reset()
    }

    // MARK: - Actions

    private func unlock() {
        guard !isLockedOut, !isBusy else {
            checkLockoutStatus()
            return
        }
        let enteredPassword = password
        password = "" // Clear from memory immediately
        isUnlocking = true
        // Opening a journal older than the last one saved here needs the password typed again
        let acceptOlder = appState.olderJournal != nil
        Task {
            let result = await appState.unlock(password: enteredPassword, acceptOlderJournal: acceptOlder)
            isUnlocking = false
            switch result {
            case .unlocked:
                break // the right password already reset the count (`AppState.unlock`)
            case .wrongPassword:
                recordFailedAttempt()
                isFocused = true
            case .olderJournal:
                // Right password, older file: the screen now asks whether to open it anyway
                error = nil
                isFocused = true
            case .failed(let message):
                error = message
            }
        }
    }

    /// Erasing is permanent: the Mac's owner confirms first (Touch ID or the login password)
    private func confirmMacOwnerThenErase() async {
        do {
            try await appState.eraseAllLocalData()
            clearFailedAttempts()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// "Forgot password" must not be a free bypass: the Mac's owner has to authenticate
    /// (login password or Touch ID). The system asks before the Keychain releases the
    /// recovery copy of the journal key; the lock is then removed and the journal opened.
    private func confirmMacOwnerThenReset() async {
        do {
            try await appState.recoverWithDeviceOwner()
            clearFailedAttempts()
        } catch AppLockVault.VaultError.recoveryKeyOutdated {
            isRecoveryOutdated = true
            self.error = AppLockVault.VaultError.recoveryKeyOutdated.localizedDescription
            showEraseConfirmation = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
