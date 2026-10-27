import SwiftUI
import Charts

/// Per-symbol breakdown cards showing detailed analytics for each ticker
struct SymbolAnalytics: View {
    let trades: [Trade]

    private var symbolGroups: [(symbol: String, trades: [Trade])] {
        let grouped = Dictionary(grouping: trades) { $0.symbol }
        return grouped.sorted { a, b in
            a.value.reduce(0) { $0 + $1.profitDouble } > b.value.reduce(0) { $0 + $1.profitDouble }
        }
        .map { (symbol: $0.key, trades: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Symbol Analytics")
                .font(.cardTitle)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(symbolGroups, id: \.symbol) { group in
                    symbolCard(symbol: group.symbol, trades: group.trades)
                }
            }
        }
    }

    private func symbolCard(symbol: String, trades: [Trade]) -> some View {
        let pnl = trades.reduce(0.0) { $0 + $1.profitDouble }
        let wins = trades.filter { $0.profitDouble > 0 }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100
        let avgR = trades.isEmpty ? 0 : trades.reduce(0.0) { $0 + $1.rMultiple } / Double(trades.count)
        let buys = trades.filter { $0.direction == .buy }.count
        let sells = trades.count - buys
        let buyPnL = trades.filter { $0.direction == .buy }.reduce(0.0) { $0 + $1.profitDouble }
        let sellPnL = trades.filter { $0.direction == .sell }.reduce(0.0) { $0 + $1.profitDouble }

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(symbol)
                    .font(.smallText)
                    .fontWeight(.bold)
                ConfidenceBadge(sampleSize: trades.count, compact: true)
                Spacer()
                Text(pnl.asCurrency)
                    .font(.smallText)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.forPnL(pnl))
            }

            // Stats row
            HStack(spacing: 16) {
                miniStat("Trades", "\(trades.count)")
                miniStat("Win", winRate.asPercent)
                miniStat("Avg R", avgR.asRMultiple)
            }

            Divider()

            // Direction split
            HStack {
                directionStat("BUY", count: buys, pnl: buyPnL)
                Spacer()
                directionStat("SELL", count: sells, pnl: sellPnL)
            }

            // Mini equity curve
            miniEquityCurve(trades: trades)
        }
        .padding(12)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
        }
    }

    private func directionStat(_ label: String, count: Int, pnl: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)
            Text("\(count)t")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Text(pnl.asCompactCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(pnl))
        }
    }

    private func miniEquityCurve(trades: [Trade]) -> some View {
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        var cumulative: Double = 0
        let points: [(index: Int, value: Double)] = sorted.enumerated().map { i, t in
            cumulative += t.profitDouble
            return (index: i, value: cumulative)
        }

        return Chart {
            ForEach(points, id: \.index) { point in
                LineMark(
                    x: .value("Trade", point.index),
                    y: .value("P&L", point.value)
                )
                .foregroundStyle(Color.accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 30)
    }
}
