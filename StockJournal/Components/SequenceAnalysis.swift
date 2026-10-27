import SwiftUI

/// Analyzes win/loss sequences for behavioral patterns
struct SequenceAnalysis: View {
    let trades: [Trade]

    private var sortedTrades: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private struct SequenceStats {
        let winAfterWin: Double  // P(win | prev win)
        let winAfterLoss: Double // P(win | prev loss)
        let lossAfterWin: Double // P(loss | prev win)
        let lossAfterLoss: Double // P(loss | prev loss)
        let avgPnLAfterWin: Double
        let avgPnLAfterLoss: Double
        let pattern: Pattern
    }

    enum Pattern: String {
        case momentum = "Momentum"    // Wins cluster, losses cluster
        case meanRevert = "Mean Reverting" // Win-loss alternation tendency
        case random = "Random"        // No discernible pattern
        case tiltRisk = "Tilt Risk"   // Bigger losses after losses
    }

    private var stats: SequenceStats? {
        guard sortedTrades.count >= 20 else { return nil }

        var ww = 0, wl = 0, lw = 0, ll = 0
        var pnlAfterWin: [Double] = []
        var pnlAfterLoss: [Double] = []

        for i in 1..<sortedTrades.count {
            let prev = sortedTrades[i - 1]
            let curr = sortedTrades[i]
            let prevWin = prev.isWin
            let currWin = curr.isWin

            if prevWin && currWin { ww += 1 }
            else if prevWin && !currWin { wl += 1 }
            else if !prevWin && currWin { lw += 1 }
            else { ll += 1 }

            if prevWin {
                pnlAfterWin.append(curr.profitDouble)
            } else {
                pnlAfterLoss.append(curr.profitDouble)
            }
        }

        let totalAfterWin = ww + wl
        let totalAfterLoss = lw + ll

        let winAfterWin = totalAfterWin > 0 ? Double(ww) / Double(totalAfterWin) * 100 : 0
        let winAfterLoss = totalAfterLoss > 0 ? Double(lw) / Double(totalAfterLoss) * 100 : 0
        let lossAfterWin = totalAfterWin > 0 ? Double(wl) / Double(totalAfterWin) * 100 : 0
        let lossAfterLoss = totalAfterLoss > 0 ? Double(ll) / Double(totalAfterLoss) * 100 : 0

        let avgAfterWin = pnlAfterWin.isEmpty ? 0 : pnlAfterWin.reduce(0, +) / Double(pnlAfterWin.count)
        let avgAfterLoss = pnlAfterLoss.isEmpty ? 0 : pnlAfterLoss.reduce(0, +) / Double(pnlAfterLoss.count)

        // Pattern detection
        let pattern: Pattern
        if lossAfterLoss > 55 && avgAfterLoss < avgAfterWin * 0.5 {
            pattern = .tiltRisk
        } else if winAfterWin > 55 && lossAfterLoss > 55 {
            pattern = .momentum
        } else if winAfterLoss > 55 && lossAfterWin > 55 {
            pattern = .meanRevert
        } else {
            pattern = .random
        }

        return SequenceStats(
            winAfterWin: winAfterWin,
            winAfterLoss: winAfterLoss,
            lossAfterWin: lossAfterWin,
            lossAfterLoss: lossAfterLoss,
            avgPnLAfterWin: avgAfterWin,
            avgPnLAfterLoss: avgAfterLoss,
            pattern: pattern
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sequence Analysis", systemImage: "arrow.triangle.branch")
                .font(.cardTitle)

            if let stats {
                // Pattern badge
                HStack(spacing: 6) {
                    Text("Pattern:")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    Text(stats.pattern.rawValue)
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(patternColor(stats.pattern))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(patternColor(stats.pattern).opacity(0.15))
                        .clipShape(Capsule())
                }

                // Transition matrix
                VStack(spacing: 4) {
                    HStack {
                        Text("")
                            .frame(width: 80)
                        Text("→ Win")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 60)
                        Text("→ Loss")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 60)
                        Text("Avg P&L")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 65)
                    }

                    transitionRow(
                        label: "After Win",
                        winPct: stats.winAfterWin,
                        lossPct: stats.lossAfterWin,
                        avgPnL: stats.avgPnLAfterWin
                    )
                    transitionRow(
                        label: "After Loss",
                        winPct: stats.winAfterLoss,
                        lossPct: stats.lossAfterLoss,
                        avgPnL: stats.avgPnLAfterLoss
                    )
                }

                // Insight
                Text(insightText(stats))
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 2)
            } else {
                Text("Need 20+ trades for sequence analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(16)
    }

    private func transitionRow(label: String, winPct: Double, lossPct: Double, avgPnL: Double) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(String(format: "%.0f%%", winPct))
                .font(.monoSubtitle)
                .foregroundStyle(Color.semanticGreen)
                .frame(width: 60)
            Text(String(format: "%.0f%%", lossPct))
                .font(.monoSubtitle)
                .foregroundStyle(Color.semanticRed)
                .frame(width: 60)
            Text(avgPnL.asCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(avgPnL))
                .frame(width: 65)
        }
    }

    private func patternColor(_ pattern: Pattern) -> Color {
        switch pattern {
        case .momentum: .blue
        case .meanRevert: .orange
        case .random: .secondary
        case .tiltRisk: Color.semanticRed
        }
    }

    private func insightText(_ stats: SequenceStats) -> String {
        switch stats.pattern {
        case .tiltRisk:
            return "Warning: Losses tend to cluster and worsen. Consider stepping away after a loss."
        case .momentum:
            return "Wins and losses tend to cluster. Stay in the zone during streaks, step back during slumps."
        case .meanRevert:
            return "Results tend to alternate. Stay disciplined — a loss doesn't predict another loss."
        case .random:
            return "No clear sequencing pattern. Each trade is independent of the previous result."
        }
    }
}
