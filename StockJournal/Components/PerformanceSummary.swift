import SwiftUI

/// Weekly and monthly performance summary cards
struct PerformanceSummary: View {
    let trades: [Trade]

    /// Weeks (from Monday) and months of the US trading calendar, like the P&L calendar
    private var calendar: Calendar { TradingCalendar.calendar }

    var body: some View {
        EqualHeightHStack(spacing: 12) {
            StretchingCard { periodCard(title: "This Week", trades: thisWeekTrades) }
            StretchingCard { periodCard(title: "This Month", trades: thisMonthTrades) }
            StretchingCard { periodCard(title: "Last Month", trades: lastMonthTrades) }
        }
    }

    // MARK: - Period Filtering

    private var thisWeekTrades: [Trade] {
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return trades.filter { $0.closeTime >= start }
    }

    private var thisMonthTrades: [Trade] {
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return trades.filter { $0.closeTime >= start }
    }

    private var lastMonthTrades: [Trade] {
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
              let interval = calendar.dateInterval(of: .month, for: lastMonth) else {
            return []
        }
        return trades.filter { $0.closeTime >= interval.start && $0.closeTime < interval.end }
    }

    // MARK: - Card

    private func periodCard(title: String, trades: [Trade]) -> some View {
        let pnl = trades.reduce(0.0) { $0 + $1.profitDouble }
        let wins = trades.filter { $0.profitDouble > 0 }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100

        return VStack(alignment: .leading, spacing: 0) {
            // Period label
            Text(title)
                .font(.custom("DM Sans", size: 15).weight(.medium))
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 8)

            // P&L value
            Text(pnl.asCurrency)
                .font(.custom("JetBrains Mono", size: 22).weight(.bold))
                .tracking(-0.5)
                .foregroundStyle(pnlColor(pnl))

            // Sub-stats row
            HStack(spacing: 12) {
                Text("\(trades.count) trades")
                    .font(.custom("JetBrains Mono", size: 14))
                    .foregroundStyle(Color.textTertiary)
                if !trades.isEmpty {
                    Text(winRate.asPercent)
                        .font(.custom("JetBrains Mono", size: 14))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.top, 8)

            // Sparkline
            if !trades.isEmpty {
                dailySparkline(trades: trades)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    private func pnlColor(_ value: Double) -> Color {
        if value > 0 { return Color.semanticGreen }
        if value < 0 { return Color.semanticRed }
        return Color.textTertiary
    }

    /// Sparkline bar chart — 4px wide bars, 24px total height
    private func dailySparkline(trades: [Trade]) -> some View {
        let daily = TradingCalendar.dailyPnL(trades)
            .sorted { $0.key < $1.key }

        let maxAbs = daily.map { abs($0.value) }.max() ?? 1

        return HStack(spacing: 2) {
            ForEach(daily, id: \.key) { _, pnl in
                let height = max(abs(pnl) / maxAbs * 24, 2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(pnl >= 0 ? Color.semanticGreen : Color.semanticRed)
                    .frame(width: 4, height: height)
            }
        }
        .frame(height: 24, alignment: .bottom)
    }
}
