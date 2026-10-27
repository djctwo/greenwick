import SwiftUI
import Charts

/// Histogram showing the distribution of trade P&L outcomes
struct WinLossDistribution: View {
    let trades: [Trade]

    struct Bucket: Identifiable {
        let id = UUID()
        let range: String
        let count: Int
        let isProfit: Bool
    }

    var buckets: [Bucket] {
        guard !trades.isEmpty else { return [] }

        let profits = trades.map { $0.profitDouble }
        let maxProfit = profits.max() ?? 0
        let maxLoss = abs(profits.min() ?? 0)
        let maxAbs = max(maxProfit, maxLoss)

        // Create 10 buckets from -maxAbs to +maxAbs
        guard maxAbs > 0 else { return [] }
        let bucketSize = maxAbs / 5

        var result: [Bucket] = []
        for i in stride(from: -5, to: 5, by: 1) {
            let low = Double(i) * bucketSize
            let high = Double(i + 1) * bucketSize
            let count = profits.filter { $0 >= low && $0 < high }.count
            if count > 0 {
                let label = "\(Int(saturating: low))"
                result.append(Bucket(range: label, count: count, isProfit: low >= 0))
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("P&L Distribution")
                    .font(.cardTitle)
                Spacer()
                let profits = trades.map { $0.profitDouble }
                if let median = median(profits) {
                    Text("Median: \(median.asCurrency)")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if buckets.isEmpty {
                Text("Not enough data")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("P&L", bucket.range),
                        y: .value("Count", bucket.count)
                    )
                    .foregroundStyle(bucket.isProfit ? Color.semanticGreen : Color.semanticRed)
                }
                .chartXAxisLabel("P&L ($)")
                .chartYAxisLabel("Trades")
                .frame(height: 150)
            }
        }
        .padding(16)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
