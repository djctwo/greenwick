import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.appState) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Configuration.AI.enabledKey) private var isAIEnabled = false
    @AppStorage(IdleLockSetting.key) private var idleLockMinutes = IdleLockSetting.defaultMinutes

    var body: some View {
        Form {
            securitySection
            aiSection
            marketDataSection
            dataSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { viewModel.loadKeysForEditing() }
        .onDisappear { viewModel.clearSensitiveFields() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                viewModel.clearSensitiveFields()
            }
        }
        .alert("Delete All Trades?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                let count = viewModel.tradeCount
                if let deletedTrades = viewModel.deleteAllTrades() {
                    appState.toast = ToastData(
                        style: .info,
                        message: "Deleted \(count) trades",
                        undoAction: { [weak viewModel] in
                            viewModel?.restoreTrades(deletedTrades)
                        }
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all \(viewModel.tradeCount) imported trades. You'll have 5 seconds to undo.")
        }
        .alert("Restore Backup?", isPresented: $viewModel.showRestoreConfirmation) {
            Button("Restore", role: .destructive) {
                Task { await viewModel.backup.beginRestore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all trades in your journal with the trades in the backup file. Trades added since that backup will be lost.")
        }
        .sheet(item: $viewModel.backup.sheet) { sheet in
            BackupSheet(model: viewModel.backup, sheet: sheet)
        }
        .sheet(item: $viewModel.passwordSheet) { sheet in
            passwordSheet(sheet)
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        Section("AI Analysis") {
            Toggle("Allow AI analysis in the Edge Report (optional, off by default)", isOn: $isAIEnabled)
                .accessibilityIdentifier("settings.aiEnabled")

            Text(Configuration.AI.dataSentDescription)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Your Anthropic API Key", text: $viewModel.anthropicAPIKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.saveAnthropicKey() }

            Button {
                viewModel.saveAnthropicKey()
            } label: {
                Label("Save API Key", systemImage: "key")
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.textSecondary)
                    .font(.smallText)
                Text("Stored securely in macOS Keychain")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Uses your own key from console.anthropic.com; Anthropic bills that account. Leave the key empty to keep AI analysis unavailable.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Market Data Section

    private var marketDataSection: some View {
        Section("Market Data") {
            // Show saved status
            if viewModel.hasSavedFinnhubKey {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.semanticGreen)
                        .font(.smallText)
                    Text("Finnhub API key saved")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            HStack(spacing: 8) {
                SecureField(viewModel.hasSavedFinnhubKey ? "Enter new key to replace" : "Finnhub API Key",
                            text: $viewModel.finnhubAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.saveFinnhubKey() }

                Button {
                    viewModel.saveFinnhubKey()
                } label: {
                    Text("Save")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.finnhubAPIKey.isEmpty)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.testFinnhubConnection() }
                } label: {
                    if viewModel.isTestingConnection {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing...")
                                .font(.smallText)
                        }
                    } else {
                        Label("Test Connection", systemImage: "wifi")
                    }
                }
                .accessibilityIdentifier("settings.testConnection")
                .disabled(viewModel.isTestingConnection || !viewModel.hasSavedFinnhubKey)

                if viewModel.hasSavedFinnhubKey {
                    Button(role: .destructive) {
                        KeychainHelper.finnhubAPIKey = nil
                        viewModel.connectionTestResult = nil
                        viewModel.statusMessage = "Finnhub API key removed"
                    } label: {
                        Label("Remove Key", systemImage: "trash")
                    }
                }
            }

            // Connection test result
            if let result = viewModel.connectionTestResult {
                switch result {
                case .success(let symbol, let price):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen)
                        Text("Connected — \(symbol) @ $\(String(format: "%.2f", price))")
                            .font(.smallText)
                            .foregroundStyle(Color.semanticGreen)
                    }
                case .failure(let error):
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.semanticRed)
                        Text(error)
                            .font(.smallText)
                            .foregroundStyle(Color.semanticRed)
                    }
                }
            }

            Text("Optional. Uses your own free key from finnhub.io/register for quotes, ticker search and company profiles in Browse and Watchlist. Only the ticker symbols you look up or watch are sent to Finnhub; your trades never are.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Imported Trades") {
                Text("\(viewModel.tradeCount)")
                    .font(.bodyText)
            }

            LabeledContent("Database Size") {
                Text(BackupService.databaseSize(at: appState.database.databasePath))
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.backup.beginExport()
                } label: {
                    Label("Back Up Journal", systemImage: "arrow.down.doc")
                }
                .accessibilityIdentifier("settings.backUpJournal")

                Button {
                    viewModel.showRestoreConfirmation = true
                } label: {
                    Label("Restore Backup", systemImage: "arrow.up.doc")
                }
                .accessibilityIdentifier("settings.restoreBackup")
            }

            Text("Backups without a password are readable by anyone who gets the file; protecting them "
                 + "with a password is recommended.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 12) {
                Button {
                    viewModel.loadSampleTrades()
                } label: {
                    Label("Load Sample Trades", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.loadSampleTrades")

                Button {
                    viewModel.removeSampleTrades()
                } label: {
                    Label("Remove Sample Trades", systemImage: "xmark.bin")
                }
                .accessibilityIdentifier("settings.removeSampleTrades")
            }
            Text("Sample trades are 30 made-up trades for exploring Greenwick. Removing them leaves your own trades untouched.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label("Delete All Trades", systemImage: "trash")
            }
            .accessibilityIdentifier("settings.deleteAllTrades")
            .disabled(viewModel.tradeCount == 0)

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section("Security") {
            if viewModel.isAppLockEnabled {
                HStack {
                    Label("App Lock", systemImage: "lock.fill")
                    Spacer()
                    Text("Enabled")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticGreen)
                }

                Picker("Lock after inactivity", selection: $idleLockMinutes) {
                    ForEach(IdleLockSetting.choices, id: \.self) { minutes in
                        Text(IdleLockSetting.label(for: minutes)).tag(minutes)
                    }
                }
                .accessibilityIdentifier("settings.idleLock")

                Button {
                    viewModel.showPasswordSheet(.change)
                } label: {
                    Label("Change Password", systemImage: "key.horizontal")
                }

                Button(role: .destructive) {
                    viewModel.showPasswordSheet(.disable)
                } label: {
                    Label("Disable App Lock", systemImage: "lock.open")
                }
            } else {
                HStack {
                    Label("App Lock", systemImage: "lock.open")
                    Spacer()
                    Text("Disabled")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }

                Button {
                    viewModel.showPasswordSheet(.enable)
                } label: {
                    Label("Enable App Lock", systemImage: "lock.fill")
                }
            }

            Text("With App Lock on, your journal is encrypted with a key that only your password unlocks: "
                 + "nothing is decrypted until you enter it. Greenwick locks again when it goes to the background "
                 + "and, unless set to Off, after the chosen time without keyboard or mouse activity in the app.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func passwordSheet(_ sheet: SettingsViewModel.PasswordSheet) -> some View {
        VStack(spacing: 20) {
            Text(sheetTitle(sheet))
                .font(.cardTitle)

            VStack(spacing: 12) {
                if sheet != .enable {
                    limitedSecureField("Current Password", text: $viewModel.currentPassword)
                }
                if sheet != .disable {
                    limitedSecureField("New Password", text: $viewModel.newPassword)
                    limitedSecureField("Confirm Password", text: $viewModel.confirmPassword)
                }
            }
            .frame(width: 260)

            if let error = viewModel.passwordError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            Text(sheet == .disable
                 ? "Your journal stays encrypted, with its key back in your Keychain."
                 : "Minimum \(AppLockVault.minimumPasswordLength) characters")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.cancelPasswordSheet()
                }
                .keyboardShortcut(.cancelAction)

                Button(sheetAction(sheet)) {
                    Task { await viewModel.submitPasswordSheet() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSavingPassword || !canSubmit(sheet))

                if viewModel.isSavingPassword {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(30)
        .frame(width: 340)
    }

    private func limitedSecureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) {
                if text.wrappedValue.count > 128 {
                    text.wrappedValue = String(text.wrappedValue.prefix(128))
                }
            }
    }

    private func sheetTitle(_ sheet: SettingsViewModel.PasswordSheet) -> String {
        switch sheet {
        case .enable: "Set App Lock Password"
        case .change: "Change Password"
        case .disable: "Disable App Lock"
        }
    }

    private func sheetAction(_ sheet: SettingsViewModel.PasswordSheet) -> String {
        switch sheet {
        case .enable: "Set Password"
        case .change: "Change Password"
        case .disable: "Disable Lock"
        }
    }

    private func canSubmit(_ sheet: SettingsViewModel.PasswordSheet) -> Bool {
        switch sheet {
        case .enable: !viewModel.newPassword.isEmpty && !viewModel.confirmPassword.isEmpty
        case .change: !viewModel.currentPassword.isEmpty && !viewModel.newPassword.isEmpty
            && !viewModel.confirmPassword.isEmpty
        case .disable: !viewModel.currentPassword.isEmpty
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
            }
            LabeledContent("Build") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
            }
            LabeledContent("Database") {
                Text("GRDB.swift (SQLite)")
            }
            LabeledContent("License") {
                Text("GNU GPL v3, free and open source")
            }
            Text("Found a bug or have an idea? Open an issue on the project's GitHub page.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
