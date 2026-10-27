import SwiftUI
import Charts

/// MAE vs MFE scatter plot showing trade execution efficiency
struct MAEMFEChart: View {
    let trades: [Trade]

    private var captureRatio: Double {
        let mfeSum = trades.map(\.mfePoints).reduce(0, +)
        guard mfeSum > 0 else { return 0 }
        let actualPoints = trades.reduce(0.0) { sum, t in
            // Approximate actual points from P&L and shares (rough estimate)
            sum + abs(t.profitDouble / max(t.shares * 10, 1))
        }
        return actualPoints / mfeSum
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAE / MFE Analysis")
                .font(.cardTitle)

            if trades.count < 5 {
                Text("Need at least 5 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(trades) { trade in
                    PointMark(
                        x: .value("MAE (pts)", trade.maePoints),
                        y: .value("MFE (pts)", trade.mfePoints)
                    )
                    .foregroundStyle(Color.forPnL(trade.profitDouble))
                    .symbolSize(25)
                    .opacity(0.7)
                }
                .chartXAxisLabel("MAE (adverse excursion, pts)", alignment: .center)
                .chartYAxisLabel("MFE (favorable excursion, pts)", alignment: .center)
                .frame(height: 180)

                // Summary stats
                HStack(spacing: 16) {
                    statItem("Avg MAE", String(format: "%.1f", avgMAE), color: .semanticRed)
                    statItem("Avg MFE", String(format: "%.1f", avgMFE), color: .semanticGreen)
                    statItem("MFE:MAE Ratio", String(format: "%.1fx", mfeToMaeRatio), color: mfeToMaeRatio >= 2 ? .semanticGreen : .orange)
                    Spacer()
                }

                // Insight
                if avgMAE > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: insightIcon)
                            .font(.smallText)
                            .foregroundStyle(insightColor)
                        Text(insightText)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private var avgMAE: Double {
        guard !trades.isEmpty else { return 0 }
        return trades.map(\.maePoints).reduce(0, +) / Double(trades.count)
    }

    private var avgMFE: Double {
        guard !trades.isEmpty else { return 0 }
        return trades.map(\.mfePoints).reduce(0, +) / Double(trades.count)
    }

    private var mfeToMaeRatio: Double {
        guard avgMAE > 0 else { return 0 }
        return avgMFE / avgMAE
    }

    private var insightText: String {
        if mfeToMaeRatio >= 3 {
            return "Excellent execution — MFE far exceeds MAE"
        } else if mfeToMaeRatio >= 2 {
            return "Good trade management — 2:1+ favorable ratio"
        } else if mfeToMaeRatio >= 1 {
            return "Average efficiency — consider tighter stops or better entries"
        } else {
            return "Drawdowns exceed favorable moves — review entry timing"
        }
    }

    private var insightIcon: String {
        mfeToMaeRatio >= 2 ? "checkmark.circle" : "exclamationmark.circle"
    }

    private var insightColor: Color {
        mfeToMaeRatio >= 2 ? .semanticGreen : .orange
    }

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
