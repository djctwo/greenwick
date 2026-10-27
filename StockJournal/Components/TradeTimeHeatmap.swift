import SwiftUI

/// Hour-by-day heatmap showing P&L concentration across the trading week
struct TradeTimeHeatmap: View {
    let trades: [Trade]

    private let days = TradingCalendar.tradingWeekdays
    private let hours = Array(0..<24)

    private struct Cell: Identifiable {
        let id: String
        let day: String
        let hour: Int
        let pnl: Double
        let count: Int
    }

    private var cells: [Cell] {
        var map: [String: (pnl: Double, count: Int)] = [:]

        for trade in trades {
            let key = "\(trade.entryWeekday)-\(trade.hour)" // entry weekday and hour, both ET
            let existing = map[key] ?? (pnl: 0, count: 0)
            map[key] = (pnl: existing.pnl + trade.profitDouble, count: existing.count + 1)
        }

        var result: [Cell] = []
        for day in days {
            for hour in hours {
                let key = "\(day)-\(hour)"
                let data = map[key] ?? (pnl: 0, count: 0)
                result.append(Cell(id: key, day: day, hour: hour, pnl: data.pnl, count: data.count))
            }
        }
        return result
    }

    private var maxAbsPnL: Double {
        cells.map { abs($0.pnl) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Time × Day Heatmap", systemImage: "square.grid.3x3")
                .font(.cardTitle)

            if trades.isEmpty {
                Text("No trade data")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Show condensed hours (6-21 UTC covers all trading)
                let displayHours = Array(6..<22)

                VStack(spacing: 1) {
                    // Header row with hours
                    HStack(spacing: 1) {
                        Text("")
                            .font(.monoSmall)
                            .frame(width: 26)
                        ForEach(displayHours, id: \.self) { hour in
                            Text("\(hour)")
                                .font(.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Data rows
                    ForEach(days, id: \.self) { day in
                        HStack(spacing: 1) {
                            Text(day)
                                .font(.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 26, alignment: .leading)

                            ForEach(displayHours, id: \.self) { hour in
                                let cell = cells.first { $0.day == day && $0.hour == hour }
                                let pnl = cell?.pnl ?? 0
                                let count = cell?.count ?? 0

                                cellView(pnl: pnl, count: count)
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.semanticRed).frame(width: 10, height: 10)
                        Text("Loss").font(.monoSmall).foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.secondary.opacity(0.1)).frame(width: 10, height: 10)
                        Text("No trades").font(.monoSmall).foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.semanticGreen).frame(width: 10, height: 10)
                        Text("Profit").font(.monoSmall).foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.top, 4)
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

    private func cellView(pnl: Double, count: Int) -> some View {
        let intensity: Double = maxAbsPnL > 0 ? min(abs(pnl) / maxAbsPnL, 1.0) : 0
        let color: Color
        if count == 0 {
            color = Color.secondary.opacity(0.05)
        } else if pnl >= 0 {
            color = Color.semanticGreen.opacity(0.15 + intensity * 0.85)
        } else {
            color = Color.semanticRed.opacity(0.15 + intensity * 0.85)
        }
        let tooltip = count > 0 ? "\(pnl.asCurrency) (\(count) trades)" : "No trades"

        return Rectangle()
            .fill(color)
            .frame(maxWidth: .infinity, minHeight: 16)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .help(tooltip)
    }
}
