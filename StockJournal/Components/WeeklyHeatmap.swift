import SwiftUI

/// Weekly P&L heatmap — shows performance patterns across weeks
struct WeeklyHeatmap: View {
    let trades: [Trade]

    private struct WeekData: Identifiable {
        let id: String
        let weekStart: Date
        let profit: Double
        let tradeCount: Int
        let winRate: Double
    }

    private var weeklyData: [WeekData] {
        // Trading weeks: Monday to Sunday of the US trading day
        let grouped = Dictionary(grouping: trades) { TradingCalendar.startOfWeek($0.closeTime) }

        return grouped.map { weekStart, weekTrades in
            let key = TradingCalendar.dayKey(weekStart)
            let profit = weekTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = weekTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(weekTrades.count) * 100
            return WeekData(id: key, weekStart: weekStart, profit: profit, tradeCount: weekTrades.count, winRate: wr)
        }.sorted { $0.weekStart < $1.weekStart }
    }

    private var maxAbsProfit: Double {
        weeklyData.map { abs($0.profit) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Weekly Performance", systemImage: "square.grid.3x3.fill")
                .font(.cardTitle)

            if weeklyData.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Heatmap grid — show last 16 weeks max
                let displayData = Array(weeklyData.suffix(16))
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: min(4, displayData.count))

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(displayData) { week in
                        weekCell(week)
                    }
                }

                // Summary
                let profitWeeks = weeklyData.filter { $0.profit > 0 }.count
                let totalWeeks = weeklyData.count
                let avgWeekly = weeklyData.map(\.profit).reduce(0, +) / Double(max(totalWeeks, 1))
                let currentStreak = calculateStreak()

                HStack(spacing: 16) {
                    statItem("Green Weeks", "\(profitWeeks)/\(totalWeeks)", color: Color.semanticGreen)
                    statItem("Avg Week", avgWeekly.asCompactCurrency, color: Color.forPnL(avgWeekly))
                    statItem("Streak", "\(currentStreak > 0 ? "+" : "")\(currentStreak)w", color: Color.forPnL(Double(currentStreak)))
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func weekCell(_ week: WeekData) -> some View {
        let formatter = TradingCalendar.formatter("M/d")

        return VStack(spacing: 2) {
            Text(formatter.string(from: week.weekStart))
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Text(week.profit.asCompactCurrency)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .foregroundStyle(Color.forPnL(week.profit))
            Text("\(week.tradeCount)t")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(cellColor(week.profit))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func cellColor(_ profit: Double) -> Color {
        let intensity = maxAbsProfit > 0 ? abs(profit) / maxAbsProfit : 0
        if profit > 0 {
            return Color.semanticGreen.opacity(0.1 + intensity * 0.3)
        } else if profit < 0 {
            return Color.semanticRed.opacity(0.1 + intensity * 0.3)
        }
        return Color.secondary.opacity(0.05)
    }

    private func statItem(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .foregroundStyle(color)
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func calculateStreak() -> Int {
        guard !weeklyData.isEmpty else { return 0 }
        var streak = 0
        for week in weeklyData.reversed() {
            if week.profit > 0 {
                if streak >= 0 { streak += 1 } else { break }
            } else if week.profit < 0 {
                if streak <= 0 { streak -= 1 } else { break }
            }
        }
        return streak
    }
}
