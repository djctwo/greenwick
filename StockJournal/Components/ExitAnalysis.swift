import SwiftUI
import Charts

/// Analyzes exit quality — compares actual exits to optimal exits using MFE, exit efficiency, and post-close continuation
struct ExitAnalysis: View {
    let trades: [Trade]

    // MARK: - Computed Metrics

    private var validTrades: [Trade] {
        trades.filter { $0.exitEfficiency != nil }
    }

    private var avgExitEfficiency: Double {
        guard !validTrades.isEmpty else { return 0 }
        return validTrades.compactMap(\.exitEfficiency).reduce(0, +) / Double(validTrades.count)
    }

    private var totalMoneyLeftOnTable: Double {
        trades.compactMap(\.moneyLeftOnTable).reduce(0, +)
    }

    private var winners: [Trade] {
        trades.filter(\.isWin)
    }

    /// % of winners with low exit efficiency (below 50%)
    private var earlyExitPercent: Double {
        guard !winners.isEmpty else { return 0 }
        let earlyExits = winners.filter { ($0.exitEfficiency ?? 100) < 50 }.count
        return Double(earlyExits) / Double(winners.count) * 100
    }

    // MARK: - Distribution Buckets

    private struct Bucket: Identifiable {
        let id: String
        let label: String
        let count: Int
    }

    private var distributionBuckets: [Bucket] {
        let efficiencies = validTrades.compactMap(\.exitEfficiency)
        let ranges: [(String, ClosedRange<Double>)] = [
            ("0-20%", 0...20), ("20-40%", 20...40), ("40-60%", 40...60),
            ("60-80%", 60...80), ("80-100%", 80...100),
        ]
        return ranges.map { label, range in
            let count = efficiencies.filter { range.contains($0) }.count
            return Bucket(id: label, label: label, count: count)
        }
    }

    // MARK: - Insight

    private var exitsEarly: Bool { avgExitEfficiency < 70 }

    private var insightText: String {
        if avgExitEfficiency < 50 {
            return "Exiting way too early — capturing less than half of available moves"
        } else if avgExitEfficiency < 70 {
            return "Exiting early — consider trailing stops to capture more of each move"
        } else if avgExitEfficiency < 85 {
            return "Solid exit timing — capturing most of the available move"
        } else {
            return "Excellent exits — near-optimal profit capture"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exit Analysis")
                .font(.cardTitle)

            if trades.count < 10 {
                Text("Need at least 10 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // Top row: gauge + money left on table
                HStack(spacing: 20) {
                    efficiencyGauge
                    Spacer()
                    moneyLeftCard
                }

                // Distribution chart
                distributionChart

                // Post-close + early exit stats
                statsRow

                // Insight
                insightBanner
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private var efficiencyGauge: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.borderCard, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.75 * avgExitEfficiency / 100)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .frame(width: 80, height: 80)

                VStack(spacing: 0) {
                    Text(String(format: "%.0f%%", avgExitEfficiency))
                        .font(.kpiValueSecondary)
                        .fontWeight(.bold)
                        .foregroundStyle(gaugeColor)
                    Text("efficiency")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private var gaugeColor: Color {
        if avgExitEfficiency >= 70 { return .semanticGreen }
        if avgExitEfficiency >= 50 { return .orange }
        return .semanticRed
    }

    private var moneyLeftCard: some View {
        VStack(alignment: .trailing, spacing: 6) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Money Left on Table")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Text(String(format: "%.1f pts", totalMoneyLeftOnTable))
                    .font(.cardTitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("Early Exit Rate")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Text(String(format: "%.0f%%", earlyExitPercent))
                    .font(.bodyText)
                    .fontWeight(.medium)
                    .foregroundStyle(earlyExitPercent > 60 ? Color.orange : .semanticGreen)
            }
        }
    }

    private var distributionChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exit Efficiency Distribution")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Chart(distributionBuckets) { bucket in
                BarMark(
                    x: .value("Range", bucket.label),
                    y: .value("Trades", bucket.count)
                )
                .foregroundStyle(Color.accent.gradient)
                .cornerRadius(3)
            }
            .chartYAxisLabel("Trades", alignment: .leading)
            .frame(height: 120)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statItem(
                "Avg Efficiency",
                String(format: "%.1f%%", avgExitEfficiency),
                color: gaugeColor
            )
            statItem(
                "Early Exit %",
                String(format: "%.1f%%", earlyExitPercent),
                color: earlyExitPercent > 50 ? .orange : Color.semanticGreen
            )
            statItem(
                "Left on Table",
                String(format: "$%.2f", totalMoneyLeftOnTable),
                color: totalMoneyLeftOnTable > 0 ? .orange : Color.semanticGreen
            )
            Spacer()
        }
    }

    private var insightBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: exitsEarly ? "exclamationmark.circle" : "checkmark.circle")
                .font(.smallText)
                .foregroundStyle(exitsEarly ? .orange : Color.semanticGreen)
            Text(insightText)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Helpers

    private func statItem(_ label: String, _ value: String, color: Color) -> some View {
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
