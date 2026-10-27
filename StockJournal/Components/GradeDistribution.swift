import SwiftUI
import Charts

/// Shows distribution of trade grades across portfolio
struct GradeDistribution: View {
    let trades: [Trade]

    private struct GradeBucket: Identifiable {
        let id: String
        let grade: String
        let count: Int
        let percent: Double
        let color: Color
    }

    private var gradeData: [GradeBucket] {
        guard !trades.isEmpty else { return [] }
        let metrics = MetricsCalculator.calculate(from: trades)

        var counts: [String: Int] = ["A": 0, "B": 0, "C": 0, "D": 0, "F": 0]
        for trade in trades {
            let grade = TradeGrader.grade(trade, portfolioMetrics: metrics)
            counts[grade.overall.rawValue, default: 0] += 1
        }

        let total = Double(trades.count)
        let gradeOrder = ["A", "B", "C", "D", "F"]
        let colors: [String: Color] = [
            "A": Color.semanticGreen,
            "B": Color.semanticGreen.opacity(0.7),
            "C": .orange,
            "D": Color.semanticRed.opacity(0.7),
            "F": Color.semanticRed,
        ]

        return gradeOrder.compactMap { grade in
            let count = counts[grade] ?? 0
            guard count > 0 else { return nil }
            return GradeBucket(
                id: grade,
                grade: grade,
                count: count,
                percent: Double(count) / total * 100,
                color: colors[grade] ?? .secondary
            )
        }
    }

    private var averageScore: Double {
        guard !trades.isEmpty else { return 0 }
        let metrics = MetricsCalculator.calculate(from: trades)
        let total = trades.reduce(0) { sum, trade in
            sum + TradeGrader.grade(trade, portfolioMetrics: metrics).total
        }
        return Double(total) / Double(trades.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trade Grades", systemImage: "graduationcap")
                .font(.cardTitle)

            if trades.count < 5 {
                Text("Need at least 5 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(spacing: 16) {
                    // Average score
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", averageScore))
                            .font(.kpiValueSecondary)
                            .fontWeight(.bold)
                            .foregroundStyle(scoreColor)
                        Text("Avg Score")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(width: 60)

                    // Bar chart
                    Chart(gradeData) { bucket in
                        BarMark(
                            x: .value("Grade", bucket.grade),
                            y: .value("Count", bucket.count)
                        )
                        .foregroundStyle(bucket.color)
                        .annotation(position: .top) {
                            Text(String(format: "%.0f%%", bucket.percent))
                                .font(.monoSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(height: 100)
                }

                // Breakdown summary
                let abCount = gradeData.filter { $0.grade == "A" || $0.grade == "B" }.map(\.count).reduce(0, +)
                let dfCount = gradeData.filter { $0.grade == "D" || $0.grade == "F" }.map(\.count).reduce(0, +)
                let abPct = Double(abCount) / Double(trades.count) * 100
                let dfPct = Double(dfCount) / Double(trades.count) * 100

                HStack(spacing: 4) {
                    Image(systemName: abPct >= 50 ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.smallText)
                        .foregroundStyle(abPct >= 50 ? Color.semanticGreen : .orange)
                    Text("\(String(format: "%.0f", abPct))% A/B trades, \(String(format: "%.0f", dfPct))% D/F trades")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private var scoreColor: Color {
        if averageScore >= 70 { return Color.semanticGreen }
        if averageScore >= 50 { return .orange }
        return Color.semanticRed
    }
}
