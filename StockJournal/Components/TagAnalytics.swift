import SwiftUI
import Charts

/// P&L breakdown by user-defined trade tags
struct TagAnalytics: View {
    let trades: [Trade]

    private struct TagData: Identifiable {
        let id: String
        let tag: String
        let profit: Double
        let tradeCount: Int
        let winRate: Double
        let avgR: Double
    }

    private var tagData: [TagData] {
        // Flatten all trades into tag -> [Trade] mapping
        var tagTrades: [String: [Trade]] = [:]
        for trade in trades {
            for tag in trade.tagList {
                tagTrades[tag, default: []].append(trade)
            }
        }

        return tagTrades.map { tag, taggedTrades in
            let profit = taggedTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = taggedTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(taggedTrades.count) * 100
            let avgR = taggedTrades.map(\.rMultiple).reduce(0, +) / Double(taggedTrades.count)
            return TagData(id: tag, tag: tag, profit: profit, tradeCount: taggedTrades.count, winRate: wr, avgR: avgR)
        }.sorted { abs($0.profit) > abs($1.profit) }
    }

    private var taggedTradeCount: Int {
        trades.filter { !$0.tagList.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tag Analysis", systemImage: "tag")
                    .font(.cardTitle)
                Spacer()
                Text("\(taggedTradeCount)/\(trades.count) tagged")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            if tagData.isEmpty {
                Text("No tagged trades yet — add tags in trade detail to see analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Bar chart
                Chart(tagData.prefix(8)) { item in
                    BarMark(
                        x: .value("P&L", item.profit),
                        y: .value("Tag", item.tag)
                    )
                    .foregroundStyle(Color.forPnL(item.profit))
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
                .frame(height: CGFloat(min(tagData.count, 8) * 28))

                // Detail rows
                ForEach(tagData.prefix(8)) { item in
                    HStack {
                        Text(item.tag)
                            .font(.monoSubtitle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accent.opacity(0.12))
                            .clipShape(Capsule())
                        Spacer()
                        Text(item.profit.asCompactCurrency)
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.forPnL(item.profit))
                        Text(String(format: "%.0f%%", item.winRate))
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 30, alignment: .trailing)
                        Text(item.avgR.asRMultiple)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.forPnL(item.avgR))
                            .frame(width: 40, alignment: .trailing)
                        Text("\(item.tradeCount)t")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 22, alignment: .trailing)
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
}
