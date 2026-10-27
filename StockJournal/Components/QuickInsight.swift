import SwiftUI

/// Surfaces a key data-driven insight at the top of the dashboard
struct QuickInsight: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    private var insight: Insight? {
        generateInsight()
    }

    var body: some View {
        if let insight {
            HStack(spacing: 12) {
                // Icon in accent-tinted square
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentDim)
                        .frame(width: 32, height: 32)
                    Image(systemName: insight.icon)
                        .font(.bodyText)
                        .foregroundStyle(Color.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.cardTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accent)
                    Text(insight.message)
                        .font(.bodyText)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.accent.opacity(0.08), Color.accent.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accent.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        }
    }

    // MARK: - Insight Generation

    private struct Insight {
        let icon: String
        let title: String
        let message: String
        let color: Color
    }

    private func generateInsight() -> Insight? {
        guard trades.count >= 5 else { return nil }

        // Use day-of-year for daily rotation
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let insights = allInsights()
        guard !insights.isEmpty else { return nil }
        return insights[dayOfYear % insights.count]
    }

    private func allInsights() -> [Insight] {
        var result: [Insight] = []

        // Best session
        let bySession = MetricsCalculator.edgeBySession(from: trades)
        if let best = bySession.max(by: { $0.profit < $1.profit }), best.profit > 0 {
            result.append(Insight(
                icon: "clock.fill",
                title: "\(best.label) is your strongest session",
                message: "\(best.profit.asCurrency) across \(best.tradeCount) trades with \(best.winRate.asPercent) win rate.",
                color: .semanticGreen
            ))
        }

        // Worst session
        if let worst = bySession.min(by: { $0.profit < $1.profit }), worst.profit < 0 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                title: "\(worst.label) is costing you",
                message: "\(worst.profit.asCurrency) over \(worst.tradeCount) trades. Consider reducing size or sitting out.",
                color: .semanticRed
            ))
        }

        // Best symbol
        let bySymbol = MetricsCalculator.edgeBySymbol(from: trades)
        if let best = bySymbol.max(by: { $0.profit < $1.profit }), best.profit > 0 {
            result.append(Insight(
                icon: "chart.bar.fill",
                title: "\(best.label) is your top symbol",
                message: "\(best.profit.asCurrency) profit, \(best.winRate.asPercent) win rate across \(best.tradeCount) trades.",
                color: .semanticGreen
            ))
        }

        // Win streak observation
        if metrics.maxWinStreak >= 5 {
            result.append(Insight(
                icon: "flame.fill",
                title: "Impressive win streak: \(metrics.maxWinStreak) in a row",
                message: "Your best streak shows strong edge exploitation. Stay disciplined.",
                color: .orange
            ))
        }

        // High win rate
        if metrics.winRate >= 60 {
            result.append(Insight(
                icon: "target",
                title: "\(metrics.winRate.asPercent) win rate — above average",
                message: "Most retail traders average 40-50%. Keep focusing on quality setups.",
                color: .semanticGreen
            ))
        }

        // Low win rate but profitable (R-based edge)
        if metrics.winRate < 50 && metrics.totalProfit > 0 {
            result.append(Insight(
                icon: "chart.bar.fill",
                title: "Profitable at \(metrics.winRate.asPercent) win rate — R-multiple edge",
                message: "Your winners outsize your losers. Avg win \(metrics.averageWin.asCurrency) vs avg loss \(metrics.averageLoss.asCurrency).",
                color: .blue
            ))
        }

        // Sharpe ratio insight
        if metrics.sharpeRatio >= 1.0 {
            result.append(Insight(
                icon: "chart.xyaxis.line",
                title: "Sharpe ratio \(String(format: "%.2f", metrics.sharpeRatio)) — excellent risk-adjusted returns",
                message: "A Sharpe above 1.0 indicates strong consistency relative to your volatility.",
                color: .semanticGreen
            ))
        } else if metrics.sharpeRatio < 0 {
            result.append(Insight(
                icon: "chart.xyaxis.line",
                title: "Negative Sharpe ratio — returns trail risk",
                message: "Focus on reducing losing trades or increasing win size to improve risk-adjusted performance.",
                color: .semanticRed
            ))
        }

        // Large drawdown warning
        if metrics.maxDrawdown > metrics.totalProfit && metrics.totalProfit > 0 {
            result.append(Insight(
                icon: "arrow.down.circle.fill",
                title: "Max drawdown exceeds total profit",
                message: "\(metrics.maxDrawdown.asCurrency) drawdown vs \(metrics.totalProfit.asCurrency) total. Tighten risk management.",
                color: .orange
            ))
        }

        // Best day
        let byDay = MetricsCalculator.edgeByDay(from: trades)
        if let best = byDay.max(by: { $0.profit < $1.profit }), best.profit > 0 {
            result.append(Insight(
                icon: "calendar",
                title: "\(best.label) is your best trading day",
                message: "\(best.profit.asCurrency) with \(best.winRate.asPercent) win rate. Consider focusing effort here.",
                color: .blue
            ))
        }

        return result
    }
}
