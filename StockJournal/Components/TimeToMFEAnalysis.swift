import SwiftUI
import Charts

/// Analyzes how quickly trades reach maximum favorable excursion and whether the trader holds too long
struct TimeToMFEAnalysis: View {
    let trades: [Trade]

    // MARK: - Data Types

    private struct MFEBucket: Identifiable {
        let id: String
        let label: String
        let count: Int
    }

    // MARK: - Filtered Data

    private var validTrades: [Trade] {
        trades.filter { $0.timeToMFEMin > 0 }
    }

    // MARK: - Distribution Buckets

    private var buckets: [MFEBucket] {
        let ranges: [(label: String, range: ClosedRange<Int>)] = [
            ("0-5m", 0...5),
            ("5-15m", 6...15),
            ("15-30m", 16...30),
            ("30-60m", 31...60),
            ("1h+", 61...999999),
        ]

        return ranges.compactMap { bucket in
            let matching = validTrades.filter { bucket.range.contains($0.timeToMFEMin) }
            guard !matching.isEmpty else { return nil }
            return MFEBucket(id: bucket.label, label: bucket.label, count: matching.count)
        }
    }

    // MARK: - Metrics

    private var medianTimeToMFE: Int {
        let sorted = validTrades.map(\.timeToMFEMin).sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? [sorted[mid - 1], sorted[mid]].overflowSafeAverage()
            : sorted[mid]
    }

    private var avgHoldTime: Int {
        validTrades.map(\.durationMin).overflowSafeAverage()
    }

    private var avgExitEfficiency: Double? {
        let efficiencies = validTrades.compactMap(\.exitEfficiency)
        guard !efficiencies.isEmpty else { return nil }
        return efficiencies.reduce(0, +) / Double(efficiencies.count)
    }

    private var isOverholding: Bool {
        medianTimeToMFE > 0 && Double(avgHoldTime) > Double(medianTimeToMFE) * 2
    }

    // MARK: - Body

    var body: some View {
        if validTrades.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 12) {
                header

                if validTrades.count < 10 {
                    Text("Need at least 10 trades with time-to-MFE data")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    distributionChart
                    metricsRow
                    if isOverholding { overholdInsight }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "stopwatch")
                .foregroundStyle(Color.accent)
            Text("Time to MFE")
                .font(.cardTitle)
            ConfidenceBadge(sampleSize: validTrades.count, compact: true)
        }
    }

    private var distributionChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Distribution")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.label),
                    y: .value("Trades", bucket.count)
                )
                .foregroundStyle(Color.accent.gradient)
                .cornerRadius(3)
                .annotation(position: .top) {
                    Text("\(bucket.count)")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .chartYAxisLabel("Trades", alignment: .leading)
            .frame(height: 140)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 16) {
            metricItem(
                "Profit Peak",
                "\(medianTimeToMFE)m",
                color: Color.accent
            )
            metricItem(
                "Avg Hold",
                "\(avgHoldTime)m",
                color: isOverholding ? .orange : .secondary
            )
            if let eff = avgExitEfficiency {
                metricItem(
                    "MFE Captured",
                    String(format: "%.0f%%", eff),
                    color: eff >= 70 ? .semanticGreen : eff >= 50 ? .orange : .semanticRed
                )
            }
            Spacer()
        }
    }

    private var overholdInsight: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle")
                .font(.smallText)
                .foregroundStyle(.orange)
            Text("Profits peak at \(medianTimeToMFE)m but you hold for \(avgHoldTime)m — consider tighter trailing stops")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Helpers

    private func metricItem(_ label: String, _ value: String, color: Color) -> some View {
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
}
