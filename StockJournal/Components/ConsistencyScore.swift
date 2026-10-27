import SwiftUI

/// Measures trading consistency across multiple dimensions
/// Consistency = how repeatable your edge is (vs. lucky streaks)
struct ConsistencyScore: View {
    let trades: [Trade]

    private struct ScoreDimension {
        let name: String
        let score: Double // 0-100
        let detail: String
    }

    private var dimensions: [ScoreDimension] {
        guard trades.count >= 10 else { return [] }

        let sorted = trades.sorted { $0.closeTime < $1.closeTime }

        return [
            winRateStability(sorted),
            profitFactorConsistency(sorted),
            drawdownRecovery(sorted),
            sizingDiscipline(sorted),
            timingConsistency(sorted),
        ]
    }

    /// Overall score = weighted average of all dimensions
    private var overallScore: Double {
        guard !dimensions.isEmpty else { return 0 }
        return dimensions.map(\.score).reduce(0, +) / Double(dimensions.count)
    }

    private var grade: Grade {
        if overallScore >= 85 { return .a }
        if overallScore >= 70 { return .b }
        if overallScore >= 55 { return .c }
        if overallScore >= 40 { return .d }
        return .f
    }

    private enum Grade {
        case a, b, c, d, f

        var label: String {
            switch self {
            case .a: "A"
            case .b: "B"
            case .c: "C"
            case .d: "D"
            case .f: "F"
            }
        }

        var color: Color {
            switch self {
            case .a: Color.semanticGreen
            case .b: Color.semanticGreen.opacity(0.7)
            case .c: .orange
            case .d: Color.semanticRed.opacity(0.7)
            case .f: Color.semanticRed
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Consistency Score", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
            }

            if trades.count < 10 {
                Text("Need at least 10 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack(spacing: 16) {
                    // Grade circle
                    ZStack {
                        Circle()
                            .stroke(grade.color.opacity(0.2), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: overallScore / 100)
                            .stroke(grade.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(grade.label)
                                .font(.kpiValueSecondary)
                                .fontWeight(.bold)
                                .foregroundStyle(grade.color)
                            Text(String(format: "%.0f", overallScore))
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(width: 64, height: 64)

                    // Dimension bars
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(dimensions, id: \.name) { dim in
                            HStack(spacing: 6) {
                                Text(dim.name)
                                    .font(.smallText)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 65, alignment: .trailing)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.secondary.opacity(0.1))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(barColor(dim.score))
                                            .frame(width: max(2, geometry.size.width * dim.score / 100))
                                    }
                                }
                                .frame(height: 8)
                                Text(String(format: "%.0f", dim.score))
                                    .font(.monoSmall)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 20)
                            }
                        }
                    }
                }

                // Weakest area callout
                if let weakest = dimensions.min(by: { $0.score < $1.score }), weakest.score < 60 {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.monoSmall)
                            .foregroundStyle(.orange)
                        Text("Focus area: \(weakest.name) — \(weakest.detail)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func barColor(_ score: Double) -> Color {
        if score >= 70 { return Color.semanticGreen }
        if score >= 50 { return .orange }
        return Color.semanticRed
    }

    // MARK: - Dimension Calculations

    /// How stable is the win rate across rolling windows?
    private func winRateStability(_ sorted: [Trade]) -> ScoreDimension {
        let windowSize = max(5, sorted.count / 4)
        var windowRates: [Double] = []
        for i in 0...(sorted.count - windowSize) {
            let window = Array(sorted[i..<(i + windowSize)])
            let wr = Double(window.filter(\.isWin).count) / Double(window.count)
            windowRates.append(wr)
        }
        guard !windowRates.isEmpty else {
            return ScoreDimension(name: "Win Rate", score: 50, detail: "Not enough data")
        }
        let mean = windowRates.reduce(0, +) / Double(windowRates.count)
        let variance = windowRates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(windowRates.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1.0 // Coefficient of variation
        let score = max(0, min(100, (1 - cv) * 100))
        return ScoreDimension(name: "Win Rate", score: score, detail: cv > 0.3 ? "Win rate varies significantly between periods" : "Stable win rate")
    }

    /// Is profit factor consistent or driven by outliers?
    private func profitFactorConsistency(_ sorted: [Trade]) -> ScoreDimension {
        let halfIdx = sorted.count / 2
        let firstHalf = Array(sorted[..<halfIdx])
        let secondHalf = Array(sorted[halfIdx...])

        let pf1 = profitFactorOf(firstHalf)
        let pf2 = profitFactorOf(secondHalf)

        guard pf1 > 0 || pf2 > 0 else {
            return ScoreDimension(name: "P/F Stability", score: 0, detail: "No profitable periods")
        }

        // Score based on how close the two halves' PFs are
        let ratio = min(pf1, pf2) / max(max(pf1, pf2), 0.01)
        let score = min(100, ratio * 100)
        return ScoreDimension(name: "P/F Stability", score: score, detail: ratio < 0.5 ? "Profit factor differs significantly between halves" : "Consistent profitability")
    }

    private func profitFactorOf(_ trades: [Trade]) -> Double {
        let gross = trades.filter(\.isWin).map(\.profitDouble).reduce(0, +)
        let loss = abs(trades.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
        return loss > 0 ? gross / loss : gross > 0 ? 10.0 : 0
    }

    /// How quickly does the trader recover from drawdowns?
    private func drawdownRecovery(_ sorted: [Trade]) -> ScoreDimension {
        var peak = 0.0, cumulative = 0.0
        var drawdownPeriods: [Int] = [] // Length of each drawdown period
        var currentDDLength = 0

        for trade in sorted {
            cumulative += trade.profitDouble
            if cumulative >= peak {
                peak = cumulative
                if currentDDLength > 0 {
                    drawdownPeriods.append(currentDDLength)
                    currentDDLength = 0
                }
            } else {
                currentDDLength += 1
            }
        }
        if currentDDLength > 0 { drawdownPeriods.append(currentDDLength) }

        guard !drawdownPeriods.isEmpty else {
            return ScoreDimension(name: "Recovery", score: 100, detail: "No drawdowns")
        }

        let avgDD = Double(drawdownPeriods.reduce(0, +)) / Double(drawdownPeriods.count)
        let maxDD = Double(drawdownPeriods.max() ?? 0)
        // Score: shorter drawdown periods = better
        let score = max(0, min(100, 100 - (avgDD / Double(sorted.count) * 200) - (maxDD > Double(sorted.count) / 3 ? 20 : 0)))
        return ScoreDimension(name: "Recovery", score: score, detail: avgDD > 5 ? "Avg \(Int(saturating: avgDD)) trades to recover from drawdowns" : "Quick recovery from drawdowns")
    }

    /// Are position sizes consistent? (Sign of discipline)
    private func sizingDiscipline(_ sorted: [Trade]) -> ScoreDimension {
        let shares = sorted.map(\.shares)
        let mean = shares.reduce(0, +) / Double(shares.count)
        guard mean > 0 else {
            return ScoreDimension(name: "Sizing", score: 50, detail: "No sizing data")
        }
        let variance = shares.map { pow($0 - mean, 2) }.reduce(0, +) / Double(shares.count)
        let cv = sqrt(variance) / mean
        let score = max(0, min(100, (1 - cv) * 100))
        return ScoreDimension(name: "Sizing", score: score, detail: cv > 0.5 ? "Position sizes vary widely — sign of revenge trading" : "Consistent position sizing")
    }

    /// Are trades happening at consistent times? (Process discipline)
    private func timingConsistency(_ sorted: [Trade]) -> ScoreDimension {
        let hours = sorted.map(\.hour)
        let uniqueHours = Set(hours)
        // Concentrated in few hours = more disciplined
        let concentration = 1.0 - (Double(uniqueHours.count) / 24.0)
        let score = min(100, concentration * 120) // Scale up slightly
        return ScoreDimension(name: "Timing", score: score, detail: uniqueHours.count > 8 ? "Trading across too many hours — pick a session" : "Focused trading hours")
    }
}
