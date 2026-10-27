import SwiftUI
import Charts

/// Analyzes trade P&L by duration buckets
struct DurationAnalysis: View {
    let trades: [Trade]

    private struct DurationBucket: Identifiable {
        let id: String
        let label: String
        let profit: Double
        let tradeCount: Int
        let winRate: Double
        let avgR: Double
    }

    private var buckets: [DurationBucket] {
        let ranges: [(label: String, range: ClosedRange<Int>)] = [
            ("0-5m", 0...5),
            ("5-15m", 6...15),
            ("15-30m", 16...30),
            ("30-60m", 31...60),
            ("1-2h", 61...120),
            ("2h+", 121...999999),
        ]

        return ranges.compactMap { bucket in
            let matching = trades.filter { bucket.range.contains($0.durationMin) }
            guard !matching.isEmpty else { return nil }
            let profit = matching.reduce(0.0) { $0 + $1.profitDouble }
            let wins = matching.filter(\.isWin).count
            let wr = Double(wins) / Double(matching.count) * 100
            let avgR = matching.map(\.rMultiple).reduce(0, +) / Double(matching.count)
            return DurationBucket(
                id: bucket.label, label: bucket.label,
                profit: profit, tradeCount: matching.count,
                winRate: wr, avgR: avgR
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration Analysis")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
            }

            if buckets.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Duration", bucket.label),
                        y: .value("P&L", bucket.profit)
                    )
                    .foregroundStyle(Color.forPnL(bucket.profit))
                    .annotation(position: bucket.profit >= 0 ? .top : .bottom) {
                        Text("\(bucket.tradeCount)t")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
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
                .frame(height: 160)

                // Summary: sweet spot duration
                if let best = buckets.max(by: { $0.avgR < $1.avgR }), best.tradeCount >= 3 {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.monoSmall)
                            .foregroundStyle(Color.accent)
                        Text("Sweet spot: \(best.label) (\(best.avgR.asRMultiple) avg R, \(String(format: "%.0f", best.winRate))% WR)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }
}
