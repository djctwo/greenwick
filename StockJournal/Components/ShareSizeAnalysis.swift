import SwiftUI
import Charts

/// Scatter plot showing relationship between share size and P&L
struct ShareSizeAnalysis: View {
    let trades: [Trade]

    private var avgSharesWins: Double {
        let wins = trades.filter(\.isWin)
        guard !wins.isEmpty else { return 0 }
        return wins.map(\.shares).reduce(0, +) / Double(wins.count)
    }

    private var avgSharesLosses: Double {
        let losses = trades.filter(\.isLoss)
        guard !losses.isEmpty else { return 0 }
        return losses.map(\.shares).reduce(0, +) / Double(losses.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share Size Analysis")
                .font(.cardTitle)

            if trades.count < 5 {
                Text("Need at least 5 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(trades) { trade in
                    PointMark(
                        x: .value("Shares", trade.shares),
                        y: .value("P&L", trade.profitDouble)
                    )
                    .foregroundStyle(Color.forPnL(trade.profitDouble))
                    .symbolSize(30)
                    .opacity(0.6)
                }
                .chartXAxisLabel("Shares", alignment: .center)
                .chartYAxisLabel("P&L ($)", alignment: .center)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                                    .font(.monoSmall)
                            }
                        }
                    }
                }
                .frame(height: 160)

                // Summary stats
                HStack(spacing: 16) {
                    statPill("Avg Win Shares", String(format: "%.0f", avgSharesWins), color: .semanticGreen)
                    statPill("Avg Loss Shares", String(format: "%.0f", avgSharesLosses), color: .semanticRed)
                    if avgSharesLosses > avgSharesWins * 1.2 {
                        Text("Oversizing on losses")
                            .font(.smallText)
                            .foregroundStyle(.orange)
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private func statPill(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(color)
        }
    }
}
