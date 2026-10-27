import AppKit
import SwiftUI

extension DatabaseManager.OlderJournal {
    /// The question shown to the owner
    var question: String {
        (errorDescription ?? "") + " Open it anyway?"
    }

    /// What is known about the file on disk
    var fileDetail: String {
        let saved = file.map { "This copy was saved " + $0.savedAt.formatted(date: .abbreviated, time: .shortened) + "." }
            ?? "This copy was saved by a version of Greenwick from before journals were numbered."
        let consequence = reason == .older
            ? " Changes made after it was saved are not in it."
            : " It may not contain what you last saved."
        return saved + " Someone may have put an older copy of your journal in its place." + consequence
    }
}

/// App Lock off: the journal on disk is older than the last one this Mac saved. Opening it
/// needs an explicit confirmation; until then it stays closed and untouched. (With App Lock
/// on, the lock screen asks for the password again instead.)
struct OlderJournalView: View {
    @Environment(\.appState) private var appState
    let older: DatabaseManager.OlderJournal

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.kpiValue)
                .foregroundStyle(Color.semanticAmber)
            Text("Older Journal")
                .font(.kpiValueSecondary)
                .fontWeight(.bold)
            Text(older.question)
                .font(.bodyText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("olderJournal.question")
            Text(older.fileDetail)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = appState.databaseError {
                Text(problem)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Quit Greenwick") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("olderJournal.quit")
                Button("Open Anyway") { appState.openOlderJournal() }
                    .accessibilityIdentifier("olderJournal.open")
            }
            Spacer()
        }
        .frame(maxWidth: 520)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
    }
}
