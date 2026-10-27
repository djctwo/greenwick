import SwiftUI
import Charts

/// Detects when and why a trader's edge is deteriorating
/// Different from ImprovementTracker: this diagnoses decay causes, not just trends
struct EdgeDecayMonitor: View {
    let trades: [Trade]

    // MARK: - Data Models

    private struct RollingPoint: Identifiable {
        let id: Int
        let tradeNumber: Int
        let date: Date
        let sharpe: Double
        let pf: Double
        let expectancy: Double
    }

    private enum DecayStatus {
        case healthy
        case warning
        case decaying

        var label: String {
            switch self {
            case .healthy: "Healthy"
            case .warning: "Warning"
            case .decaying: "Decaying"
            }
        }

        var color: Color {
            switch self {
            case .healthy: .semanticGreen
            case .warning: .orange
            case .decaying: .semanticRed
            }
        }

        var icon: String {
            switch self {
            case .healthy: "checkmark.seal.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .decaying: "chart.line.downtrend.xyaxis"
            }
        }
    }

    private struct DecayDiagnosis: Identifiable {
        let id = UUID()
        let dimension: String
        let detail: String
        let severity: DecayStatus
    }

    // MARK: - Computed Properties

    private let windowSize = 30
    private var sorted: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private var rollingData: [RollingPoint] {
        guard sorted.count >= windowSize else { return [] }
        var points: [RollingPoint] = []

        for i in (windowSize - 1)..<sorted.count {
            let window = Array(sorted[(i - windowSize + 1)...i])
            let profits = window.map(\.profitDouble)
            let wins = window.filter(\.isWin)
            let losses = window.filter(\.isLoss)
            let grossWin = wins.reduce(0.0) { $0 + $1.profitDouble }
            let grossLoss = abs(losses.reduce(0.0) { $0 + $1.profitDouble })
            let winRate = Double(wins.count) / Double(window.count)
            let avgWin = wins.isEmpty ? 0 : grossWin / Double(wins.count)
            let avgLoss = losses.isEmpty ? 0 : grossLoss / Double(losses.count)

            let pf = grossLoss > 0 ? grossWin / grossLoss : grossWin > 0 ? 5.0 : 0
            let expectancy = (winRate * avgWin) - ((1 - winRate) * avgLoss)

            // Simplified Sharpe: mean / stddev of trade returns
            let mean = profits.reduce(0, +) / Double(profits.count)
            let variance = profits.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(profits.count)
            let stddev = sqrt(variance)
            let sharpe = stddev > 0 ? mean / stddev : 0

            points.append(RollingPoint(
                id: i,
                tradeNumber: i + 1,
                date: window.last!.closeTime, // safe: window is non-empty
                sharpe: min(max(sharpe, -3), 3), // clamp for chart
                pf: min(pf, 5),
                expectancy: expectancy
            ))
        }
        return points
    }

    private var status: DecayStatus {
        guard rollingData.count >= 2 else { return .healthy }
        let recent = Array(rollingData.suffix(windowSize))
        let prior = Array(rollingData.dropLast(windowSize).suffix(windowSize))
        guard !prior.isEmpty, !recent.isEmpty else { return .healthy }

        let recentAvgPF = recent.map(\.pf).reduce(0, +) / Double(recent.count)
        let priorAvgPF = prior.map(\.pf).reduce(0, +) / Double(prior.count)
        let recentAvgExp = recent.map(\.expectancy).reduce(0, +) / Double(recent.count)
        let priorAvgExp = prior.map(\.expectancy).reduce(0, +) / Double(prior.count)

        // Decay: PF dropped > 0.5 or expectancy dropped > 30%
        let pfDrop = priorAvgPF - recentAvgPF
        let expDropPct = priorAvgExp != 0 ? (priorAvgExp - recentAvgExp) / abs(priorAvgExp) : 0

        if pfDrop > 0.5 || expDropPct > 0.3 { return .decaying }
        if pfDrop > 0.25 || expDropPct > 0.15 { return .warning }
        return .healthy
    }

    private var diagnoses: [DecayDiagnosis] {
        guard status != .healthy, sorted.count >= windowSize * 2 else { return [] }
        var results: [DecayDiagnosis] = []
        let midpoint = sorted.count / 2
        let firstHalf = Array(sorted.prefix(midpoint))
        let secondHalf = Array(sorted.suffix(sorted.count - midpoint))

        // Overtrading detection: frequency up + edge down
        let firstDays = TradingCalendar.tradingDayCount(firstHalf)
        let secondDays = TradingCalendar.tradingDayCount(secondHalf)
        let firstFreq = firstDays > 0 ? Double(firstHalf.count) / Double(firstDays) : 0
        let secondFreq = secondDays > 0 ? Double(secondHalf.count) / Double(secondDays) : 0
        if secondFreq > firstFreq * 1.3 {
            results.append(DecayDiagnosis(
                dimension: "Overtrading",
                detail: String(format: "Trade frequency up %.0f%% (%.1f → %.1f/day)", (secondFreq / firstFreq - 1) * 100, firstFreq, secondFreq),
                severity: secondFreq > firstFreq * 1.5 ? .decaying : .warning
            ))
        }

        // Session drift: new sessions or hours appearing
        let firstSessions = Set(firstHalf.map { $0.session })
        let secondSessions = Set(secondHalf.map { $0.session })
        let newSessions = secondSessions.subtracting(firstSessions)
        if !newSessions.isEmpty {
            let names = newSessions.map(\.displayName).joined(separator: ", ")
            results.append(DecayDiagnosis(
                dimension: "Strategy Drift",
                detail: "New sessions: \(names)",
                severity: .warning
            ))
        }

        // Per-session decay check
        for session in MarketSession.allCases {
            let firstSession = firstHalf.filter { $0.session == session }
            let secondSession = secondHalf.filter { $0.session == session }
            guard firstSession.count >= 10, secondSession.count >= 10 else { continue }
            let firstWR = Double(firstSession.filter(\.isWin).count) / Double(firstSession.count) * 100
            let secondWR = Double(secondSession.filter(\.isWin).count) / Double(secondSession.count) * 100
            if firstWR - secondWR > 15 {
                results.append(DecayDiagnosis(
                    dimension: "\(session.displayName) Decay",
                    detail: String(format: "Win rate dropped %.0f%% → %.0f%%", firstWR, secondWR),
                    severity: (firstWR - secondWR) > 25 ? .decaying : .warning
                ))
            }
        }

        return results
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Edge Decay Monitor", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.cardTitle)
                ConfidenceBadge(sampleSize: trades.count)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: status.icon)
                    Text(status.label)
                        .fontWeight(.semibold)
                }
                .font(.smallText)
                .foregroundStyle(status.color)
            }

            if sorted.count < windowSize * 2 {
                Text("Need at least \(windowSize * 2) trades to detect decay patterns")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Rolling Sharpe chart with regime overlay
                rollingChart

                // Diagnoses
                if !diagnoses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Possible Causes")
                            .font(.smallText)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.textSecondary)

                        ForEach(diagnoses) { diag in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(diag.severity.color)
                                    .frame(width: 6, height: 6)
                                Text(diag.dimension)
                                    .font(.smallText)
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .leading)
                                Text(diag.detail)
                                    .font(.smallText)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                } else if status == .healthy {
                    Text("Your edge appears stable across all dimensions")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticGreen)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Rolling Chart

    private var rollingChart: some View {
        Chart {
            ForEach(rollingData) { point in
                LineMark(
                    x: .value("Trade", point.tradeNumber),
                    y: .value("Sharpe", point.sharpe)
                )
                .foregroundStyle(Color.semanticBlue)

            }

            // Zero line
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                .foregroundStyle(Color.textTertiary)
        }
        .chartYAxisLabel("Rolling Sharpe")
        .chartXAxisLabel("Trade #")
        .frame(height: 160)
    }

}
