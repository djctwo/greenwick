import SwiftUI
import Charts

/// Histogram showing distribution of trade outcomes in R-multiples
struct RMultipleChart: View {
    let trades: [Trade]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("R-Multiple Distribution")
                .font(.cardTitle)

            if trades.isEmpty {
                Text("Import trades to see R-multiple distribution")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(buckets, id: \.range) { bucket in
                    BarMark(
                        x: .value("R-Multiple", bucket.range),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(bucket.midpoint >= 0 ? Color.semanticGreen : Color.semanticRed)
                }
                .chartXAxisLabel("R-Multiple")
                .chartYAxisLabel("Trade Count")
                .frame(height: 200)

                // Summary stats
                HStack(spacing: 20) {
                    summaryItem("Avg R", value: avgR.asRMultiple, color: Color.forPnL(avgR))
                    summaryItem("Median R", value: medianR.asRMultiple, color: Color.forPnL(medianR))
                    summaryItem("Best", value: bestR.asRMultiple, color: .semanticGreen)
                    summaryItem("Worst", value: worstR.asRMultiple, color: .semanticRed)
                }
            }
        }
        .padding(16)
    }

    private func summaryItem(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    // MARK: - Bucketing

    struct Bucket {
        let range: String
        let count: Int
        let midpoint: Double
    }

    private var buckets: [Bucket] {
        let rValues = trades.map(\.rMultiple)
        guard !rValues.isEmpty else { return [] }

        // Create buckets from -3R to +3R in 0.5R increments
        let ranges: [(Double, Double)] = [
            (-100, -2.0), (-2.0, -1.5), (-1.5, -1.0), (-1.0, -0.5), (-0.5, 0.0),
            (0.0, 0.5), (0.5, 1.0), (1.0, 1.5), (1.5, 2.0), (2.0, 100)
        ]

        return ranges.compactMap { (low, high) in
            let count = rValues.filter { $0 >= low && $0 < high }.count
            guard count > 0 else { return nil }

            let label: String
            if low <= -100 { label = "<-2R" }
            else if high >= 100 { label = ">2R" }
            else { label = "\(String(format: "%.1f", low))R" }

            return Bucket(range: label, count: count, midpoint: (low + high) / 2)
        }
    }

    private var avgR: Double {
        let vals = trades.map(\.rMultiple)
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }

    private var medianR: Double {
        let sorted = trades.map(\.rMultiple).sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private var bestR: Double { trades.map(\.rMultiple).max() ?? 0 }
    private var worstR: Double { trades.map(\.rMultiple).min() ?? 0 }
}
