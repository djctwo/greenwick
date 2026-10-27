import SwiftUI

/// Monthly returns table — professional-grade P&L breakdown by month/year
struct MonthlyReturns: View {
    let trades: [Trade]

    struct MonthData: Identifiable {
        let id: String // "2026-01"
        let year: Int
        let month: Int
        let profit: Double
        let tradeCount: Int
        let winRate: Double
    }

    private var monthlyData: [MonthData] { Self.monthlyData(for: trades) }

    /// P&L per month (of the US trading day), oldest first
    static func monthlyData(for trades: [Trade]) -> [MonthData] {
        let grouped = Dictionary(grouping: trades) { TradingCalendar.monthKey($0.closeTime) }

        return grouped.map { key, monthTrades in
            let comps = key.split(separator: "-")
            let year = Int(comps[0]) ?? 0
            let month = Int(comps[1]) ?? 0
            let profit = monthTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = monthTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(monthTrades.count) * 100
            return MonthData(id: key, year: year, month: month, profit: profit, tradeCount: monthTrades.count, winRate: wr)
        }.sorted { $0.id < $1.id }
    }

    private var years: [Int] {
        Array(Set(monthlyData.map(\.year))).sorted()
    }

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monthly Returns", systemImage: "calendar.badge.clock")
                .font(.cardTitle)

            if monthlyData.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Table header
                HStack(spacing: 0) {
                    Text("Year")
                        .frame(width: 40, alignment: .leading)
                    ForEach(0..<12, id: \.self) { i in
                        Text(monthNames[i])
                            .frame(maxWidth: .infinity)
                    }
                    Text("Total")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.monoSubtitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)

                Divider()

                // Year rows
                ForEach(years, id: \.self) { year in
                    HStack(spacing: 0) {
                        Text(verbatim: String(year)) // Text("\(year)") would show "2,026"
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                            .frame(width: 40, alignment: .leading)

                        ForEach(1...12, id: \.self) { month in
                            let data = monthlyData.first { $0.year == year && $0.month == month }
                            monthCell(data)
                                .frame(maxWidth: .infinity)
                        }

                        let yearTotal = monthlyData.filter { $0.year == year }.map(\.profit).reduce(0, +)
                        Text(yearTotal.asCompactCurrency)
                            .font(.monoSubtitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.forPnL(yearTotal))
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                // Best/worst month
                if let best = monthlyData.max(by: { $0.profit < $1.profit }),
                   let worst = monthlyData.min(by: { $0.profit < $1.profit }),
                   (1...12).contains(best.month),
                   (1...12).contains(worst.month) {
                    Divider()
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.smallText)
                                .foregroundStyle(Color.semanticGreen)
                            Text("Best: \(monthNames[best.month - 1]) \(best.year) (\(best.profit.asCompactCurrency))")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.smallText)
                                .foregroundStyle(Color.semanticRed)
                            Text("Worst: \(monthNames[worst.month - 1]) \(worst.year) (\(worst.profit.asCompactCurrency))")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
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

    private func monthCell(_ data: MonthData?) -> some View {
        Group {
            if let data {
                VStack(spacing: 0) {
                    Text(data.profit.asCompactCurrency)
                        .font(.monoSmall)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.forPnL(data.profit))
                    Text("\(data.tradeCount)t")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
                .background(Color.forPnL(data.profit).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Text("-")
                    .font(.monoSmall)
                    .foregroundStyle(.quaternary)
            }
        }
    }
}
