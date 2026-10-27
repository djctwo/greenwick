import SwiftUI

/// Shown when the database cannot be initialized even after recovery.
/// Replaces the previous fatalError() crash with a user-friendly screen.
struct DatabaseFailedView: View {
    let errorMessage: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.kpiValue)
                .foregroundStyle(Color.semanticRed)

            Text("Database Error")
                .font(.kpiValueSecondary)
                .fontWeight(.bold)

            Text(errorMessage)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                Button("Quit & Relaunch") {
                    // Let go of the data folder first, or the new copy would find it in use
                    // ("Greenwick is already open")
                    AppState.shared.shutdown()
                    // Relaunch the app via NSWorkspace
                    let url = Bundle.main.bundleURL
                    let config = NSWorkspace.OpenConfiguration()
                    config.createsNewApplicationInstance = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderedProminent)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
    }
}
