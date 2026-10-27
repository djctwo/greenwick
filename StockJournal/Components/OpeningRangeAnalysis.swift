import SwiftUI
import Charts

/// Analyzes performance based on when during the market day trades are entered
struct OpeningRangeAnalysis: View {
    let trades: [Trade]

    // MARK: - Types

    private struct TimeBucket: Identifiable {
        let id: String
        let label: String
        let tradeCount: Int
        let winRate: Double
        let avgPnL: Double
        let totalPnL: Double
    }

    // MARK: - Computed Data

    /// Minutes since market open (9:30 ET) for a trade's open time
    private func minutesSinceOpen(_ trade: Trade) -> Int? {
        let totalMinutes = TradingCalendar.minuteOfDay(trade.openTime)
        let marketOpen = TradingCalendar.market.regularOpen   // 9:30 ET
        let marketClose = TradingCalendar.market.regularClose // 16:00 ET

        // Only classify regular session trades
        guard totalMinutes >= marketOpen && totalMinutes < marketClose else { return nil }
        return totalMinutes - marketOpen
    }

    private struct BucketRange {
        let id: String
        let label: String
        let startMin: Int  // minutes since 9:30
        let endMin: Int
    }

    private let bucketRanges: [BucketRange] = [
        BucketRange(id: "5min", label: "First 5 min", startMin: 0, endMin: 5),
        BucketRange(id: "15min", label: "First 15 min", startMin: 5, endMin: 15),
        BucketRange(id: "30min", label: "First 30 min", startMin: 15, endMin: 30),
        BucketRange(id: "midmorn", label: "Mid-Morning", startMin: 30, endMin: 120),
        BucketRange(id: "lunch", label: "Lunch", startMin: 120, endMin: 210),
        BucketRange(id: "afternoon", label: "Afternoon", startMin: 210, endMin: 330),
        BucketRange(id: "power", label: "Power Hour", startMin: 330, endMin: 390),
    ]

    private var buckets: [TimeBucket] {
        bucketRanges.map { range in
            let matching = trades.filter { trade in
                guard let mins = minutesSinceOpen(trade) else { return false }
                return mins >= range.startMin && mins < range.endMin
            }

            let avgPnL = matching.isEmpty ? 0 : matching.map(\.profitDouble).reduce(0, +) / Double(matching.count)
            let totalPnL = matching.map(\.profitDouble).reduce(0, +)
            let wins = matching.filter(\.isWin).count
            let winRate = matching.isEmpty ? 0 : Double(wins) / Double(matching.count) * 100

            return TimeBucket(
                id: range.id,
                label: range.label,
                tradeCount: matching.count,
                winRate: winRate,
                avgPnL: avgPnL,
                totalPnL: totalPnL
            )
        }
    }

    private var activeBuckets: [TimeBucket] {
        buckets.filter { $0.tradeCount > 0 }
    }

    private var bestBucket: TimeBucket? {
        activeBuckets.max(by: { $0.avgPnL < $1.avgPnL })
    }

    private var worstBucket: TimeBucket? {
        activeBuckets.min(by: { $0.avgPnL < $1.avgPnL })
    }

    private var hasData: Bool {
        !activeBuckets.isEmpty
    }

    private var insightText: String {
        guard let best = bestBucket, let worst = worstBucket,
              best.id != worst.id else {
            return "Need more trades across different times for insights"
        }

        let bestAvg = best.avgPnL >= 0 ? "+\(best.avgPnL.asCurrency)" : best.avgPnL.asCurrency
        let worstCost = worst.totalPnL < 0 ? abs(worst.totalPnL).asCurrency : worst.avgPnL.asCurrency

        if worst.totalPnL < 0 {
            return "Your best entries are \(best.label.lowercased()) (\(bestAvg) avg) \u{2014} \(worst.label.lowercased()) costs you \(worstCost)"
        } else {
            return "Your best entries are \(best.label.lowercased()) (\(bestAvg) avg)"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Opening Range", systemImage: "clock.arrow.circlepath")
                .font(.cardTitle)

            if !hasData {
                Text("No regular session trades to analyze")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Avg P&L bar chart by time bucket
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Time", bucket.label),
                        y: .value("Avg P&L", bucket.avgPnL)
                    )
                    .foregroundStyle(barColor(for: bucket))
                    .cornerRadius(3)
                }
                .frame(height: 110)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.borderSubtle)
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                            .font(.monoSmall)
                    }
                }

                // Detail rows
                VStack(spacing: 4) {
                    // Header
                    HStack {
                        Text("Time")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Trades")
                            .frame(width: 50, alignment: .trailing)
                        Text("Win %")
                            .frame(width: 50, alignment: .trailing)
                        Text("Avg P&L")
                            .frame(width: 70, alignment: .trailing)
                        Text("Total")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)

                    ForEach(buckets) { bucket in
                        bucketRow(bucket)
                    }
                }

                // Insight
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.semanticAmber)
                        .font(.smallText)
                    Text(insightText)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private func bucketRow(_ bucket: TimeBucket) -> some View {
        let isBest = bucket.id == bestBucket?.id && activeBuckets.count > 1
        let isWorst = bucket.id == worstBucket?.id && activeBuckets.count > 1

        return HStack {
            HStack(spacing: 4) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.monoSmall)
                        .foregroundStyle(Color.semanticGreen)
                }
                if isWorst && bucket.avgPnL < 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.monoSmall)
                        .foregroundStyle(Color.semanticRed)
                }
                Text(bucket.label)
                    .font(.monoSmall)
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(bucket.tradeCount > 0 ? "\(bucket.tradeCount)" : "-")
                .frame(width: 50, alignment: .trailing)
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)

            Text(bucket.tradeCount > 0 ? bucket.winRate.asPercent : "-")
                .frame(width: 50, alignment: .trailing)
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)

            Text(bucket.tradeCount > 0 ? bucket.avgPnL.asCurrency : "-")
                .frame(width: 70, alignment: .trailing)
                .font(.monoSmall)
                .foregroundStyle(bucket.tradeCount > 0 ? Color.forPnL(bucket.avgPnL) : Color.textTertiary)

            Text(bucket.tradeCount > 0 ? bucket.totalPnL.asCurrency : "-")
                .frame(width: 70, alignment: .trailing)
                .font(.monoSmall)
                .foregroundStyle(bucket.tradeCount > 0 ? Color.forPnL(bucket.totalPnL) : Color.textTertiary)
        }
    }

    private func barColor(for bucket: TimeBucket) -> Color {
        guard bucket.tradeCount > 0 else { return Color.textTertiary.opacity(0.3) }

        let isBest = bucket.id == bestBucket?.id && activeBuckets.count > 1
        let isWorst = bucket.id == worstBucket?.id && activeBuckets.count > 1

        if isBest { return Color.semanticGreen.opacity(0.9) }
        if isWorst && bucket.avgPnL < 0 { return Color.semanticRed.opacity(0.9) }
        return bucket.avgPnL >= 0 ? Color.semanticGreen.opacity(0.5) : Color.semanticRed.opacity(0.5)
    }
}
