import SwiftUI
import Charts

/// Analyzes how trade volume correlates with performance
struct VolumeAnalysis: View {
    let trades: [Trade]

    // MARK: - Computed Data

    private struct VolumeBucket: Identifiable {
        let id: String
        let label: String
        let tradeCount: Int
        let avgPnL: Double
        let winRate: Double
        let totalPnL: Double
    }

    private var tradesWithVolume: [Trade] {
        trades.filter { $0.volume > 0 && $0.avgVolume > 0 }
    }

    private var hasVolumeData: Bool {
        !tradesWithVolume.isEmpty
    }

    private func relativeVolume(for trade: Trade) -> Double {
        guard trade.avgVolume > 0 else { return 0 }
        return Double(trade.volume) / Double(trade.avgVolume)
    }

    private var buckets: [VolumeBucket] {
        let ranges: [(String, String, ClosedRange<Double>)] = [
            ("low", "Low (<0.5x)", 0...0.5),
            ("normal", "Normal (0.5-1.5x)", 0.5...1.5),
            ("high", "High (1.5-3x)", 1.5...3.0),
            ("vhigh", "Very High (>3x)", 3.0...1000.0),
        ]

        return ranges.map { id, label, range in
            let matching = tradesWithVolume.filter { range.contains(relativeVolume(for: $0)) }
            let avgPnL = matching.isEmpty ? 0 : matching.map(\.profitDouble).reduce(0, +) / Double(matching.count)
            let totalPnL = matching.map(\.profitDouble).reduce(0, +)
            let wins = matching.filter(\.isWin).count
            let winRate = matching.isEmpty ? 0 : Double(wins) / Double(matching.count) * 100
            return VolumeBucket(
                id: id,
                label: label,
                tradeCount: matching.count,
                avgPnL: avgPnL,
                winRate: winRate,
                totalPnL: totalPnL
            )
        }
    }

    private var insightText: String {
        let highBuckets = tradesWithVolume.filter { relativeVolume(for: $0) > 1.5 }
        let lowBuckets = tradesWithVolume.filter { relativeVolume(for: $0) < 0.5 }

        let highAvg = highBuckets.isEmpty ? 0 : highBuckets.map(\.profitDouble).reduce(0, +) / Double(highBuckets.count)
        let lowAvg = lowBuckets.isEmpty ? 0 : lowBuckets.map(\.profitDouble).reduce(0, +) / Double(lowBuckets.count)

        if highBuckets.isEmpty && lowBuckets.isEmpty {
            return "Most trades occur at normal relative volume"
        }

        let highStr = highAvg >= 0 ? "+\(highAvg.asCurrency)" : highAvg.asCurrency
        let lowStr = lowAvg >= 0 ? "+\(lowAvg.asCurrency)" : lowAvg.asCurrency

        return "Trades on high relative volume days average \(highStr) vs \(lowStr) on low volume"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Volume Analysis", systemImage: "chart.bar.doc.horizontal")
                .font(.cardTitle)

            if !hasVolumeData {
                Text("Import volume data for analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Section 1: Relative Volume buckets
                Text("Relative Volume")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Bucket", bucket.label),
                        y: .value("Avg P&L", bucket.avgPnL)
                    )
                    .foregroundStyle(bucket.avgPnL >= 0 ? Color.semanticGreen.opacity(0.7) : Color.semanticRed.opacity(0.7))
                    .cornerRadius(3)
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.borderSubtle)
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.textTertiary)
                            .font(.monoSmall)
                    }
                }

                // Bucket details
                VStack(spacing: 4) {
                    ForEach(buckets) { bucket in
                        if bucket.tradeCount > 0 {
                            HStack {
                                Text(bucket.label)
                                    .font(.monoSmall)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(bucket.tradeCount)t")
                                    .font(.monoSmall)
                                    .foregroundStyle(Color.textTertiary)
                                Text(bucket.winRate.asPercent)
                                    .font(.monoSmall)
                                    .foregroundStyle(Color.textSecondary)
                                Text(bucket.avgPnL.asCurrency)
                                    .font(.monoSmall)
                                    .foregroundStyle(Color.forPnL(bucket.avgPnL))
                            }
                        }
                    }
                }

                // Section 2: Insight
                Text("Volume vs P&L")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.top, 4)

                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.semanticAmber)
                        .font(.smallText)
                    Text(insightText)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
    }
}
