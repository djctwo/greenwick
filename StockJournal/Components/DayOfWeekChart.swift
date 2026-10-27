import SwiftUI
import Charts

/// Bar chart showing P&L by day of week (the weekday of each trade's US trading day)
struct DayOfWeekChart: View {
    let trades: [Trade]

    struct DayData: Identifiable {
        let id: String
        let day: String
        let profit: Double
        let tradeCount: Int
        let winRate: Double
    }

    private static let dayOrder = TradingCalendar.tradingWeekdays

    private var data: [DayData] { Self.data(for: trades) }

    /// P&L, trade count and win rate per weekday, Monday first; days without trades are left out
    static func data(for trades: [Trade]) -> [DayData] {
        let grouped = TradingCalendar.groupedByWeekday(trades)
        return dayOrder.compactMap { day in
            guard let dayTrades = grouped[day], !dayTrades.isEmpty else { return nil }
            let profit = dayTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = dayTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(dayTrades.count) * 100
            return DayData(id: day, day: day, profit: profit, tradeCount: dayTrades.count, winRate: wr)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("P&L by Day")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
            }

            if data.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("P&L", item.profit)
                    )
                    .foregroundStyle(Color.forPnL(item.profit))
                    .annotation(position: item.profit >= 0 ? .top : .bottom) {
                        VStack(spacing: 0) {
                            Text(item.profit.asCompactCurrency)
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.forPnL(item.profit))
                            Text("\(item.tradeCount)t")
                                .font(.monoSmall)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
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
                .frame(height: 180)

                // Best/worst day
                if let best = data.max(by: { $0.profit < $1.profit }),
                   let worst = data.min(by: { $0.profit < $1.profit }) {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Text("Best:")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                            Text("\(best.day) (\(best.profit.asCompactCurrency))")
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.semanticGreen)
                        }
                        HStack(spacing: 4) {
                            Text("Worst:")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                            Text("\(worst.day) (\(worst.profit.asCompactCurrency))")
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.semanticRed)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
    }
}
