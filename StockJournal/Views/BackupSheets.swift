import SwiftUI

/// Sheets for "Back Up Journal" (options) and restoring a password-protected backup
struct BackupSheet: View {
    @Bindable var model: BackupFlowModel
    let sheet: BackupFlowModel.Sheet

    var body: some View {
        VStack(spacing: 18) {
            switch sheet {
            case .export: exportOptions
            case .restorePassword: restorePassword
            }

            if let error = model.error {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("backup.error")
            }

            HStack(spacing: 12) {
                Button("Cancel") { model.close() }
                    .keyboardShortcut(.cancelAction)
                Button(sheet == .export ? "Choose Location…" : "Restore") {
                    Task {
                        if sheet == .export { await model.export() } else { await model.submitRestorePassword() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking || !canSubmit)
                .accessibilityIdentifier("backup.submit")
                if model.isWorking { ProgressView().controlSize(.small) }
            }
        }
        .padding(30)
        .frame(width: 380)
    }

    private var exportOptions: some View {
        VStack(spacing: 14) {
            Text("Back Up Journal")
                .font(.cardTitle)
            Toggle("Protect this backup with a password", isOn: $model.protectWithPassword)
                .accessibilityIdentifier("backup.protect")
            if model.protectWithPassword {
                VStack(spacing: 10) {
                    limitedSecureField("Backup Password", text: $model.password)
                    limitedSecureField("Confirm Password", text: $model.confirmation)
                }
                .frame(width: 260)
                Text("Minimum \(AppLockVault.minimumPasswordLength) characters. Without this password the "
                     + "backup can't be restored, and Greenwick can't recover it for you.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A backup without a password is readable by anyone who gets the file. "
                     + "Protecting it with a password is recommended.")
                    .font(.smallText)
                    .foregroundStyle(Color.semanticAmber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("backup.plainWarning")
            }
        }
    }

    private var restorePassword: some View {
        VStack(spacing: 14) {
            Text("Password-Protected Backup")
                .font(.cardTitle)
            Text("Enter the password this backup was protected with. Your journal is only "
                 + "replaced if the password is right and the backup checks out.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            limitedSecureField("Backup Password", text: $model.password)
                .frame(width: 260)
                .onSubmit { Task { await model.submitRestorePassword() } }
        }
    }

    private var canSubmit: Bool {
        switch sheet {
        case .export: !model.protectWithPassword || (!model.password.isEmpty && !model.confirmation.isEmpty)
        case .restorePassword: !model.password.isEmpty
        }
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
}
