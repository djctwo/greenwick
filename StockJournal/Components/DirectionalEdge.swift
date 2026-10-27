import SwiftUI
import Charts

/// Compares long vs short trade performance
struct DirectionalEdge: View {
    let trades: [Trade]

    private var buyTrades: [Trade] { trades.filter { $0.direction == .buy } }
    private var sellTrades: [Trade] { trades.filter { $0.direction == .sell } }

    private struct DirectionStats {
        let count: Int
        let totalPnL: Double
        let winRate: Double
        let avgR: Double
        let avgPnL: Double
    }

    private func stats(for filtered: [Trade]) -> DirectionStats {
        guard !filtered.isEmpty else {
            return DirectionStats(count: 0, totalPnL: 0, winRate: 0, avgR: 0, avgPnL: 0)
        }
        let wins = filtered.filter(\.isWin).count
        let totalPnL = filtered.map(\.profitDouble).reduce(0, +)
        let avgR = filtered.map(\.rMultiple).reduce(0, +) / Double(filtered.count)
        return DirectionStats(
            count: filtered.count,
            totalPnL: totalPnL,
            winRate: Double(wins) / Double(filtered.count) * 100,
            avgR: avgR,
            avgPnL: totalPnL / Double(filtered.count)
        )
    }

    private var buyStats: DirectionStats { stats(for: buyTrades) }
    private var sellStats: DirectionStats { stats(for: sellTrades) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Long vs Short", systemImage: "arrow.up.arrow.down")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
            }

            if trades.isEmpty {
                Text("No trade data")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Direction comparison chart
                Chart {
                    BarMark(
                        x: .value("P&L", buyStats.totalPnL),
                        y: .value("Dir", "Long")
                    )
                    .foregroundStyle(Color.forPnL(buyStats.totalPnL))

                    BarMark(
                        x: .value("P&L", sellStats.totalPnL),
                        y: .value("Dir", "Short")
                    )
                    .foregroundStyle(Color.forPnL(sellStats.totalPnL))
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                            }
                        }
                    }
                }
                .frame(height: 60)

                // Stats table
                HStack {
                    Text("")
                        .frame(width: 50)
                    Text("Trades")
                        .frame(width: 50)
                    Text("P&L")
                        .frame(width: 65)
                    Text("WR")
                        .frame(width: 45)
                    Text("Avg R")
                        .frame(width: 50)
                }
                .font(.smallText)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)

                dirRow("Long", buyStats)
                dirRow("Short", sellStats)

                // Insight
                let betterDir = buyStats.avgPnL > sellStats.avgPnL ? "Long" : "Short"
                let betterPnL = max(buyStats.avgPnL, sellStats.avgPnL)
                if buyStats.count >= 5 && sellStats.count >= 5 {
                    Text("\(betterDir) trades average \(betterPnL.asCurrency)/trade — consider leaning into this direction.")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private func dirRow(_ label: String, _ s: DirectionStats) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 50, alignment: .leading)
            Text("\(s.count)")
                .font(.monoSubtitle)
                .frame(width: 50)
            Text(s.totalPnL.asCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(s.totalPnL))
                .frame(width: 65)
            Text(s.winRate.asPercent)
                .font(.monoSubtitle)
                .frame(width: 45)
            Text(s.avgR.asRMultiple)
                .font(.monoSubtitle)
                .frame(width: 50)
        }
    }
}
