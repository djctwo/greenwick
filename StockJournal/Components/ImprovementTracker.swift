import SwiftUI
import Charts

/// Shows whether the trader is improving over time using rolling metrics
struct ImprovementTracker: View {
    let trades: [Trade]

    private struct RollingMetric: Identifiable {
        let id: Int
        let tradeNumber: Int
        let rollingWinRate: Double
        let rollingAvgR: Double
        let rollingPF: Double
    }

    private var rollingMetrics: [RollingMetric] {
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        guard sorted.count >= 20 else { return [] }

        let windowSize = max(10, sorted.count / 10)
        var metrics: [RollingMetric] = []

        for i in (windowSize - 1)..<sorted.count {
            let window = Array(sorted[(i - windowSize + 1)...i])
            let wins = window.filter(\.isWin).count
            let wr = Double(wins) / Double(window.count) * 100
            let avgR = window.map(\.rMultiple).reduce(0, +) / Double(window.count)
            let grossWin = window.filter(\.isWin).map(\.profitDouble).reduce(0, +)
            let grossLoss = abs(window.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
            let pf = grossLoss > 0 ? grossWin / grossLoss : grossWin > 0 ? 5.0 : 0

            metrics.append(RollingMetric(
                id: i,
                tradeNumber: i + 1,
                rollingWinRate: wr,
                rollingAvgR: avgR,
                rollingPF: min(pf, 5) // Cap at 5 for chart readability
            ))
        }

        return metrics
    }

    private var trend: Trend {
        guard rollingMetrics.count >= 10 else { return .insufficient }
        let half = rollingMetrics.count / 2
        let firstHalf = Array(rollingMetrics[..<half])
        let secondHalf = Array(rollingMetrics[half...])

        let firstAvgR = firstHalf.map(\.rollingAvgR).reduce(0, +) / Double(firstHalf.count)
        let secondAvgR = secondHalf.map(\.rollingAvgR).reduce(0, +) / Double(secondHalf.count)
        let firstWR = firstHalf.map(\.rollingWinRate).reduce(0, +) / Double(firstHalf.count)
        let secondWR = secondHalf.map(\.rollingWinRate).reduce(0, +) / Double(secondHalf.count)

        let rImproved = secondAvgR > firstAvgR + 0.1
        let wrImproved = secondWR > firstWR + 2

        if rImproved && wrImproved { return .improving }
        if secondAvgR < firstAvgR - 0.2 || secondWR < firstWR - 5 { return .declining }
        return .stable
    }

    private enum Trend {
        case improving, stable, declining, insufficient

        var label: String {
            switch self {
            case .improving: "Improving"
            case .stable: "Stable"
            case .declining: "Declining"
            case .insufficient: "Need more data"
            }
        }

        var color: Color {
            switch self {
            case .improving: Color.semanticGreen
            case .stable: .secondary
            case .declining: Color.semanticRed
            case .insufficient: Color.secondary.opacity(0.5)
            }
        }

        var icon: String {
            switch self {
            case .improving: "arrow.up.right.circle.fill"
            case .stable: "equal.circle.fill"
            case .declining: "arrow.down.right.circle.fill"
            case .insufficient: "questionmark.circle"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Improvement Tracker", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: trend.icon)
                        .font(.smallText)
                        .foregroundStyle(trend.color)
                    Text(trend.label)
                        .font(.smallText)
                        .fontWeight(.medium)
                        .foregroundStyle(trend.color)
                }
            }

            if trades.count < 20 {
                Text("Need at least 20 trades to track improvement")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Rolling win rate chart
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rolling Win Rate")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    Chart(rollingMetrics) { point in
                        LineMark(
                            x: .value("Trade #", point.tradeNumber),
                            y: .value("Win Rate", point.rollingWinRate)
                        )
                        .foregroundStyle(Color.accent)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(saturating: v))%")
                                        .font(.monoSmall)
                                }
                            }
                        }
                    }
                    .frame(height: 60)
                }

                // Rolling Avg R chart
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rolling Avg R-Multiple")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    Chart(rollingMetrics) { point in
                        LineMark(
                            x: .value("Trade #", point.tradeNumber),
                            y: .value("Avg R", point.rollingAvgR)
                        )
                        .foregroundStyle(Color.forPnL(point.rollingAvgR))

                        RuleMark(y: .value("Zero", 0))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                    .frame(height: 60)
                }

                // Insight
                HStack(spacing: 4) {
                    Image(systemName: trend.icon)
                        .font(.smallText)
                        .foregroundStyle(trend.color)
                    Text(insightText)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
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

    private var insightText: String {
        switch trend {
        case .improving:
            return "Your recent performance shows improvement in both win rate and risk management"
        case .stable:
            return "Performance is consistent — maintain your current approach"
        case .declining:
            return "Recent metrics are declining — review recent trades for process drift"
        case .insufficient:
            return "Keep trading to build enough history for trend detection"
        }
    }
}
