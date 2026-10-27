import SwiftUI
import Charts

/// Heatmap showing P&L by hour and day of week — only active hours shown
struct SessionHeatmap: View {
    let trades: [Trade]

    private let days = TradingCalendar.tradingWeekdays

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Heatmap")
                .font(.cardTitle)

            // Date range subtitle
            if !trades.isEmpty {
                Text(dateRangeLabel)
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            if trades.isEmpty {
                Text("Import trades to see your heatmap")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let data = heatmapData
                let activeHours = sortedActiveHours

                // Grid-based heatmap — only active hours
                VStack(spacing: 3) {
                    // Header row with hour labels
                    HStack(spacing: 3) {
                        Text("")
                            .frame(width: 36)
                        ForEach(activeHours, id: \.self) { hour in
                            Text("\(hour):00")
                                .font(.monoSmall)
                                .foregroundStyle(Color.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Day rows
                    ForEach(days, id: \.self) { day in
                        HStack(spacing: 3) {
                            Text(day)
                                .font(.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 36, alignment: .trailing)

                            ForEach(activeHours, id: \.self) { hour in
                                let cell = data.first { $0.day == day && $0.hour == hour }
                                let profit = cell?.profit ?? 0
                                let count = cell?.tradeCount ?? 0

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(cellColor(for: profit, hasData: count > 0))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .overlay {
                                        if count > 0 {
                                            VStack(spacing: 1) {
                                                Text(profit.asCompactCurrency)
                                                    .font(.monoSmall)
                                                    .foregroundStyle(Color.textPrimary)
                                                Text("\(count)t")
                                                    .font(.monoSmall)
                                                    .foregroundStyle(Color.textTertiary)
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticGreen.opacity(0.5))
                            .frame(width: 12, height: 12)
                        Text("Profit")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.semanticRed.opacity(0.5))
                            .frame(width: 12, height: 12)
                        Text("Loss")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("\(trades.count) trades")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
    }

    // MARK: - Date Range

    private var dateRangeLabel: String {
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        guard let first = sorted.first, let last = sorted.last else { return "" }
        let fmt = TradingCalendar.formatter("MMM d")
        let yearFmt = TradingCalendar.formatter(", yyyy")
        let hours = sortedActiveHours.count
        return "\(fmt.string(from: first.closeTime)) – \(fmt.string(from: last.closeTime))\(yearFmt.string(from: last.closeTime)) · \(hours) active hour\(hours == 1 ? "" : "s") · \(trades.count) trades"
    }

    // MARK: - Data

    struct HeatmapCell: Identifiable {
        let id: String
        let hour: Int
        let day: String
        let profit: Double
        let tradeCount: Int
    }

    private var heatmapData: [HeatmapCell] {
        let grouped = Dictionary(grouping: trades) { trade in
            "\(trade.entryWeekday)-\(trade.hour)" // entry weekday and hour, both ET
        }

        var cells: [HeatmapCell] = []
        for day in days {
            for hour in sortedActiveHours {
                let key = "\(day)-\(hour)"
                let dayTrades = grouped[key] ?? []
                let profit = dayTrades.reduce(0.0) { $0 + $1.profitDouble }
                cells.append(HeatmapCell(
                    id: key,
                    hour: hour,
                    day: day,
                    profit: profit,
                    tradeCount: dayTrades.count
                ))
            }
        }
        return cells
    }

    /// Only hours where trades actually happened, sorted
    private var sortedActiveHours: [Int] {
        Array(Set(trades.map(\.hour))).sorted()
    }

    private func cellColor(for profit: Double, hasData: Bool) -> Color {
        guard hasData else {
            return Color.bgInset
        }
        if profit > 0 {
            let intensity = min(abs(profit) / maxAbsProfit, 1.0)
            return Color.semanticGreen.opacity(0.2 + intensity * 0.8)
        } else if profit < 0 {
            let intensity = min(abs(profit) / maxAbsProfit, 1.0)
            return Color.semanticRed.opacity(0.2 + intensity * 0.8)
        }
        return Color.bgInset
    }

    private var maxAbsProfit: Double {
        heatmapData.map { abs($0.profit) }.max() ?? 1.0
    }
}
