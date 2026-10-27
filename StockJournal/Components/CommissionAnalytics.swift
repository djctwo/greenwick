import SwiftUI
import Charts

/// Analyzes the impact of trading costs (commissions + fees) on performance
struct CommissionAnalytics: View {
    let trades: [Trade]

    // MARK: - Computed Properties

    private var hasCostData: Bool {
        trades.contains { $0.totalCosts != 0 }
    }

    private var totalCommissions: Double {
        trades.reduce(0.0) { $0 + $1.commissionDouble }
    }

    private var totalSwap: Double {
        trades.reduce(0.0) { $0 + $1.swapDouble }
    }

    private var totalCosts: Double {
        totalCommissions + totalSwap
    }

    private var avgCostPerTrade: Double {
        trades.isEmpty ? 0 : totalCosts / Double(trades.count)
    }

    /// Gross profit of winning trades before costs (trade P&L is stored net of costs)
    private var grossProfit: Double {
        trades.map { $0.profitDouble + $0.totalCosts }.filter { $0 > 0 }.reduce(0, +)
    }

    private var costPercent: Double {
        grossProfit > 0 ? (abs(totalCosts) / grossProfit) * 100 : 0
    }

    private var symbolCosts: [SymbolCost] {
        Dictionary(grouping: trades) { $0.symbol }
            .map { symbol, group in
                let costs = group.reduce(0.0) { $0 + $1.totalCosts }
                let shares = group.reduce(0.0) { $0 + $1.shares }
                return SymbolCost(symbol: symbol, totalCosts: costs, totalShares: shares)
            }
            .sorted { abs($0.totalCosts) > abs($1.totalCosts) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Commission & Cost Analysis", systemImage: "banknote")
                .font(.cardTitle)

            if hasCostData {
                costContent
            } else {
                emptyState
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accent)
                Text("No commissions or fees recorded. Add costs to trades in the trade detail view to see cost analysis.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Tracking costs reveals hidden drags on performance. Even small per-trade fees compound over hundreds of trades.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cost Content

    private var costContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Metric cards row
            HStack(spacing: 8) {
                costPill("Commissions", totalCommissions.asCurrency)
                costPill("Fees", totalSwap.asCurrency)
                costPill("Total Costs", totalCosts.asCurrency)
                costPill("Avg/Trade", avgCostPerTrade.asCurrency)
            }

            // Cost as % of gross profit
            insightBanner

            // Bar chart: costs by symbol
            if symbolCosts.count > 1 {
                Text("COSTS BY SYMBOL")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)

                Chart(symbolCosts) { item in
                    BarMark(
                        x: .value("Symbol", item.symbol),
                        y: .value("Cost", abs(item.totalCosts))
                    )
                    .foregroundStyle(Color.accent.opacity(0.7))
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCurrency)
                                    .font(.monoSmall)
                            }
                        }
                    }
                }
            }

            // Cost per share
            if !symbolCosts.isEmpty {
                Text("COST PER SHARE")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 12) {
                    ForEach(symbolCosts.prefix(5)) { item in
                        VStack(spacing: 2) {
                            Text(item.symbol)
                                .font(.monoSubtitle)
                                .fontWeight(.semibold)
                            Text(item.costPerShare.asCurrency)
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Insight Banner

    private var insightBanner: some View {
        let color: Color = costPercent < 5 ? .semanticGreen : costPercent < 15 ? .yellow : .semanticRed
        let icon = costPercent < 5 ? "checkmark.circle.fill" : costPercent < 15 ? "exclamationmark.triangle.fill" : "xmark.octagon.fill"

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.smallText)
            Text("Costs consume \(String(format: "%.1f", costPercent))% of gross profit")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Helpers

    private func costPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Types

private struct SymbolCost: Identifiable {
    let symbol: String
    let totalCosts: Double
    let totalShares: Double
    var id: String { symbol }

    var costPerShare: Double {
        totalShares > 0 ? abs(totalCosts) / totalShares : 0
    }
}
