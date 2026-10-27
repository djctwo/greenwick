import SwiftUI
import Charts

/// Analyzes slippage patterns and their impact on P&L
struct SlippageAnalysis: View {
    let trades: [Trade]

    private var tradesWithSlippage: [Trade] {
        trades.filter { $0.slippagePoints > 0 }
    }

    private var avgSlippage: Double {
        let slippages = tradesWithSlippage.map(\.slippagePoints)
        guard !slippages.isEmpty else { return 0 }
        return slippages.reduce(0, +) / Double(slippages.count)
    }

    private var totalSlippageCost: Double {
        // Approximate: slippage points × $1/point per share × shares
        tradesWithSlippage.reduce(0.0) { total, trade in
            total + trade.slippagePoints * trade.shares
        }
    }

    private var highSlippageTrades: Int {
        tradesWithSlippage.filter { $0.slippagePoints > avgSlippage * 2 }.count
    }

    private struct BucketData: Identifiable {
        let id: String
        let label: String
        let count: Int
        let avgPnL: Double
    }

    private var buckets: [BucketData] {
        let ranges: [(String, ClosedRange<Double>)] = [
            ("0-0.5", 0...0.5),
            ("0.5-1", 0.5...1.0),
            ("1-2", 1.0...2.0),
            ("2-3", 2.0...3.0),
            ("3+", 3.0...100.0),
        ]

        return ranges.map { label, range in
            let matching = trades.filter { range.contains($0.slippagePoints) }
            let avgPnL = matching.isEmpty ? 0 : matching.map(\.profitDouble).reduce(0, +) / Double(matching.count)
            return BucketData(id: label, label: label, count: matching.count, avgPnL: avgPnL)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Slippage Analysis", systemImage: "arrow.up.and.down.and.sparkles")
                .font(.cardTitle)

            if tradesWithSlippage.isEmpty {
                Text("No slippage data available")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Key stats
                HStack(spacing: 16) {
                    statPill("Avg Slip", String(format: "%.1f pts", avgSlippage))
                    statPill("Est. Cost", totalSlippageCost.asCurrency)
                    statPill("High Slip", "\(highSlippageTrades) trades")
                }

                // Slippage distribution chart
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Slippage", bucket.label),
                        y: .value("Trades", bucket.count)
                    )
                    .foregroundStyle(bucket.avgPnL >= 0 ? Color.semanticGreen.opacity(0.7) : Color.semanticRed.opacity(0.7))
                }
                .frame(height: 100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }

                // Insight
                if avgSlippage > 1.5 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.smallText)
                        Text("Average slippage of \(String(format: "%.1f", avgSlippage)) pts is high. Consider limit orders or tighter execution windows.")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
