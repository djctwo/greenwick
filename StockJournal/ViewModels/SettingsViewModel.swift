import Foundation
import os

/// ViewModel for the Settings view
@Observable
@MainActor
final class SettingsViewModel {
    private let repository: TradeRepository
    private let appState: AppState
    private nonisolated static let logger = Logger(subsystem: "com.greenwick", category: "SettingsVM")

    var anthropicAPIKey: String = ""
    var finnhubAPIKey: String = ""
    var tradeCount: Int = 0
    var showDeleteConfirmation = false
    var showRestoreConfirmation = false
    var statusMessage: String?
    /// Back Up Journal / Restore Backup (with password protection)
    var backup: BackupFlowModel

    // App lock
    enum PasswordSheet: Identifiable {
        case enable, change, disable
        var id: Self { self }
    }
    var isAppLockEnabled: Bool { appState.isAppLockEnabled }
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmPassword: String = ""
    var passwordSheet: PasswordSheet?
    var passwordError: String?
    var isSavingPassword = false

    init(repository: TradeRepository, appState: AppState) {
        self.repository = repository
        self.appState = appState
        self.backup = BackupFlowModel(appState: appState)
        loadStats()
        backup.onRestored = { [weak self] in self?.loadStats() }
    }

    /// Load API keys from Keychain into memory for editing (call on view appear)
    func loadKeysForEditing() {
        anthropicAPIKey = KeychainHelper.anthropicAPIKey ?? ""
        finnhubAPIKey = KeychainHelper.finnhubAPIKey ?? ""
    }

    /// Clear API keys from memory (call on view disappear)
    func clearSensitiveFields() {
        anthropicAPIKey = ""
        finnhubAPIKey = ""
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
    }

    func saveAnthropicKey() {
        let key = anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainHelper.anthropicAPIKey = key.isEmpty ? nil : key
        anthropicAPIKey = "" // Clear from memory after save
        statusMessage = key.isEmpty ? "Anthropic API key removed" : "Anthropic API key saved in your Keychain"
    }

    /// Whether a Finnhub key is stored in Keychain (independent of the text field)
    var hasSavedFinnhubKey: Bool {
        KeychainHelper.finnhubAPIKey != nil
    }

    func saveFinnhubKey() {
        KeychainHelper.finnhubAPIKey = finnhubAPIKey.isEmpty ? nil : finnhubAPIKey
        finnhubAPIKey = "" // Clear from memory after save
        statusMessage = "Finnhub API key saved securely"
    }

    // MARK: - Finnhub Connection Test

    var isTestingConnection = false
    var connectionTestResult: ConnectionTestResult?

    enum ConnectionTestResult {
        case success(symbol: String, price: Double)
        case failure(String)
    }

    func testFinnhubConnection() async {
        isTestingConnection = true
        connectionTestResult = nil

        guard let apiKey = KeychainHelper.finnhubAPIKey, !apiKey.isEmpty else {
            connectionTestResult = .failure("No API key saved")
            isTestingConnection = false
            return
        }

        do {
            // Direct test request bypassing StockDataService for reliability
            guard let url = URL(string: "https://finnhub.io/api/v1/quote?symbol=AAPL") else {
                connectionTestResult = .failure("Invalid URL")
                isTestingConnection = false
                return
            }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
            request.timeoutInterval = 15

            let (data, response) = try await CertificatePinningDelegate.pinnedSession(timeout: 15).data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                connectionTestResult = .failure("Invalid response")
                isTestingConnection = false
                return
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                connectionTestResult = .failure("Invalid API key (HTTP \(httpResponse.statusCode))")
            } else if httpResponse.statusCode == 429 {
                connectionTestResult = .failure("Rate limited — try again in a moment")
            } else if httpResponse.statusCode == 200 {
                let quote = try JSONDecoder().decode(StockQuote.self, from: data)
                connectionTestResult = .success(symbol: "AAPL", price: quote.currentPrice)
            } else {
                connectionTestResult = .failure("HTTP \(httpResponse.statusCode)")
            }
        } catch {
            connectionTestResult = .failure(error.localizedDescription)
        }

        isTestingConnection = false
    }

    func loadStats() {
        do {
            tradeCount = try repository.count()
        } catch {
            Self.logger.error("Failed to load stats: \(error.localizedDescription)")
        }
    }

    /// Add the 30 fictional sample trades (skips any already present)
    func loadSampleTrades() {
        do {
            let added = try repository.loadSampleTrades()
            tradeCount = try repository.count()
            statusMessage = added > 0 ? "Added \(added) fictional sample trades" : "Sample trades are already loaded"
            Self.logger.info("Loaded \(added) sample trades")
        } catch {
            statusMessage = "Couldn't add sample trades: \(error.localizedDescription)"
        }
    }

    /// Remove only the fictional sample trades
    func removeSampleTrades() {
        do {
            let removed = try repository.deleteSampleTrades()
            tradeCount = try repository.count()
            statusMessage = removed > 0 ? "Removed \(removed) sample trades" : "There are no sample trades to remove"
        } catch {
            statusMessage = "Couldn't remove sample trades: \(error.localizedDescription)"
        }
    }

    /// Deletes all trades and returns them for potential undo
    func deleteAllTrades() -> [Trade]? {
        do {
            let trades = try repository.fetchAll()
            try repository.deleteAll()
            tradeCount = 0
            statusMessage = "All trades deleted"
            Self.logger.info("All trades deleted by user (\(trades.count) trades)")
            return trades
        } catch {
            statusMessage = "Failed to delete: \(error.localizedDescription)"
            return nil
        }
    }

    /// Restores previously deleted trades (undo operation)
    func restoreTrades(_ trades: [Trade]) {
        do {
            let inserted = try repository.bulkInsert(trades)
            tradeCount = try repository.count()
            statusMessage = "Restored \(inserted) trades"
            Self.logger.info("Undo: restored \(inserted) trades")
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - App Lock

    func showPasswordSheet(_ sheet: PasswordSheet) {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
        passwordSheet = sheet
    }

    func cancelPasswordSheet() {
        clearPasswordFields()
        passwordError = nil
        passwordSheet = nil
    }

    /// Enable, change or disable App Lock, depending on the open sheet
    func submitPasswordSheet() async {
        guard let sheet = passwordSheet, !isSavingPassword else { return }
        if sheet != .disable {
            guard !newPassword.isEmpty else { passwordError = "Password cannot be empty"; return }
            guard newPassword == confirmPassword else { passwordError = "Passwords do not match"; return }
            guard newPassword.count >= AppLockVault.minimumPasswordLength else {
                passwordError = "Password must be at least \(AppLockVault.minimumPasswordLength) characters"
                return
            }
        }
        isSavingPassword = true
        defer { isSavingPassword = false }
        do {
            switch sheet {
            case .enable:
                switch try await appState.enableAppLock(password: newPassword) {
                case .done(hasRecovery: true):
                    statusMessage = "App lock enabled. Your journal is now encrypted with your password. If you "
                        + "forget it, Touch ID or your Mac password can remove the lock."
                case .done(hasRecovery: false):
                    statusMessage = "App lock enabled. Your journal is now encrypted with your password. This copy "
                        + "of Greenwick can't keep a Touch ID recovery key, so if you forget the password the only "
                        + "way back in is erasing the journal."
                case .finishesAtNextUnlock:
                    // Until then the lock-off key is still stored as it was before
                    statusMessage = Self.finishesAtNextUnlock("App lock enabled")
                        + " Until then the journal's previous key also stays in your Keychain, as it was with App "
                        + "Lock off, so lock and unlock Greenwick soon."
                }
            case .change:
                let change = try await appState.changeAppLockPassword(current: currentPassword, new: newPassword)
                statusMessage = change == .finishesAtNextUnlock
                    ? Self.finishesAtNextUnlock("App lock password changed")
                    : "App lock password changed"
            case .disable:
                try await appState.disableAppLock(password: currentPassword)
                statusMessage = "App lock disabled"
            }
            clearPasswordFields()
            passwordError = nil
            passwordSheet = nil
        } catch {
            passwordError = error.localizedDescription
        }
    }

    /// The new password is already the one that unlocks; only the re-encryption is pending
    private static func finishesAtNextUnlock(_ done: String) -> String {
        "\(done). From now on, use the new password to unlock. Greenwick couldn't finish re-encrypting the "
            + "journal and its screenshots just now; it finishes that the next time you unlock."
    }

    private func clearPasswordFields() {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
    }
}
