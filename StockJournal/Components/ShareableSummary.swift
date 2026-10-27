import SwiftUI
import AppKit

/// Generates a copy-pasteable text summary for sharing on Discord/Telegram
struct ShareableSummary: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false

    private var summaryText: String {
        guard metrics.totalTrades > 0 else { return "" }

        let pnlSign = metrics.totalProfit >= 0 ? "+" : ""
        let streakIcon = metrics.currentStreak > 0 ? "🔥" : metrics.currentStreak < 0 ? "❄️" : "➖"
        let streakDir = metrics.currentStreak > 0 ? "W" : metrics.currentStreak < 0 ? "L" : ""

        return """
        📊 Greenwick Daily Summary
        ─────────────────────
        P&L: \(pnlSign)\(metrics.totalProfit.asCurrency) | \(metrics.totalTrades) trades
        Win Rate: \(metrics.winRate.asPercent) (\(metrics.wins)W/\(metrics.losses)L)
        PF: \(metrics.profitFactor.asProfitFactor) | Exp: \(metrics.expectancy.asCurrency)
        Avg R: \(metrics.averageRMultiple.asRMultiple) | Sharpe: \(String(format: "%.2f", metrics.sharpeRatio))
        Streak: \(streakIcon) \(abs(metrics.currentStreak))\(streakDir)
        ─────────────────────
        via Greenwick
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Share Summary", systemImage: "square.and.arrow.up")
                    .font(.cardTitle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summaryText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                    // Non-cancellable: clears clipboard even if view is dismissed
                    Task.detached {
                        try? await Task.sleep(for: .seconds(5))
                        await MainActor.run { _ = NSPasteboard.general.clearContents() }
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.smallText)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            Text(summaryText)
                .font(.monoSubtitle)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgContent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
