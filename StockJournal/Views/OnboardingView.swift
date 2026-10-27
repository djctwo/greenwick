import SwiftUI

/// Simple onboarding screen for first launch
struct OnboardingView: View {
    @Environment(\.appState) private var appState
    @State private var showSampleConfirmation = false
    let isFirstTime: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text("Welcome to Greenwick")
                .font(.kpiValue)
                .foregroundStyle(Color.textPrimary)

            Text("A private trade journal for stocks and day trading")
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "list.bullet.rectangle", title: "Trade Journal", desc: "Track every trade with notes, tags, and emotions")
                featureRow(icon: "chart.bar.xaxis", title: "Analytics Dashboard", desc: "66 analytics components to find your edge")
                featureRow(icon: "target", title: "Edge Report", desc: "Where you make and lose money, plus optional AI tips (your own key)")
                featureRow(icon: "square.and.arrow.down", title: "CSV Import", desc: "Import from ThinkorSwim, IBKR, Webull, and more")
            }
            .padding(.horizontal, 40)

            Button {
                UserDefaults.standard.set(true, forKey: "onboarding_complete")
            } label: {
                Text("Get Started")
                    .accessibilityIdentifier("onboarding.getStarted")
                    .font(.bodyText)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 200, height: 44)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                showSampleConfirmation = true
            } label: {
                Label("Load Sample Trades", systemImage: "sparkles")
                    .font(.smallText)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accent)
            .accessibilityIdentifier("onboarding.loadSampleTrades")
            .alert("Load Sample Trades?", isPresented: $showSampleConfirmation) {
                Button("Load") { loadSampleTrades() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This adds 30 fictional sample trades (made-up tickers, prices and results) so you can "
                     + "explore Greenwick before importing your own. You can remove them any time in "
                     + "Settings > Data > Remove Sample Trades.")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgApp)
    }

    /// Add the sample trades and continue into the journal
    private func loadSampleTrades() {
        do {
            let added = try appState.tradeRepository.loadSampleTrades()
            appState.showToast(.success, added > 0
                ? "Added \(added) fictional sample trades"
                : "Sample trades are already loaded")
            UserDefaults.standard.set(true, forKey: "onboarding_complete")
        } catch {
            appState.showToast(.error, "Couldn't add sample trades")
        }
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.kpiValueSecondary)
                .foregroundStyle(Color.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textPrimary)
                Text(desc)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
