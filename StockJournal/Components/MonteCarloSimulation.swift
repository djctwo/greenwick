import SwiftUI
import Charts

/// Monte Carlo simulation — randomizes trade sequence 1,000 times to project
/// probability distributions of future equity outcomes
struct MonteCarloSimulation: View {
    let trades: [Trade]

    private let simulationCount = 1000
    private let percentiles: [Double] = [0.05, 0.25, 0.50, 0.75, 0.95]

    // MARK: - Simulation Engine

    private struct SimulationResult {
        let bands: [PercentileBand]
        let probProfit: Double        // % of sims that ended profitable
        let probTarget: Double        // % that hit 2× current P&L
        let probDrawdown20: Double    // % that hit 20% drawdown
        let medianFinalPnL: Double
        let worstCase: Double         // 5th percentile final
        let bestCase: Double          // 95th percentile final
    }

    private struct PercentileBand: Identifiable {
        let id = UUID()
        let label: String
        let points: [Double]  // P&L at each trade index
        let color: Color
        let opacity: Double
    }

    private var result: SimulationResult? {
        let pnls = trades.sorted { $0.closeTime < $1.closeTime }.map(\.profitDouble)
        guard pnls.count >= 15 else { return nil }

        let tradeCount = pnls.count
        var allFinals: [Double] = []
        // Store cumulative curves for percentile bands: [simIndex][tradeIndex]
        var allCurves: [[Double]] = []

        for _ in 0..<simulationCount {
            let shuffled = pnls.shuffled()
            var cumulative = 0.0
            var curve: [Double] = [0]
            for pnl in shuffled {
                cumulative += pnl
                curve.append(cumulative)
            }
            allCurves.append(curve)
            allFinals.append(cumulative)
        }

        allFinals.sort()

        // Build percentile bands at each trade index
        let bandCount = tradeCount + 1
        var bandData: [[Double]] = Array(repeating: [], count: percentiles.count)

        for idx in 0..<bandCount {
            var valuesAtIdx = allCurves.map { $0[idx] }
            valuesAtIdx.sort()
            for (pIdx, pct) in percentiles.enumerated() {
                let position = Int(Double(simulationCount - 1) * pct)
                bandData[pIdx].append(valuesAtIdx[position])
            }
        }

        let bandConfigs: [(String, Color, Double)] = [
            ("5th", Color.semanticRed, 0.15),
            ("25th", Color.semanticAmber, 0.2),
            ("Median", Color.accent, 0.8),
            ("75th", Color.semanticCyan, 0.2),
            ("95th", Color.semanticGreen, 0.15),
        ]

        let bands = zip(bandData, bandConfigs).map { data, config in
            PercentileBand(label: config.0, points: data, color: config.1, opacity: config.2)
        }

        // Probability calculations
        let totalPnL = pnls.reduce(0, +)
        let target = max(totalPnL * 2, 500) // 2× current P&L or $500

        let probProfit = Double(allFinals.filter { $0 > 0 }.count) / Double(simulationCount)
        let probTarget = Double(allFinals.filter { $0 >= target }.count) / Double(simulationCount)

        // Drawdown check: what % of sims hit 20% of peak drawdown?
        let peakEquity = max(totalPnL, 1000) // Assume at least $1K account context
        let ddThreshold = peakEquity * 0.20
        var ddCount = 0
        for curve in allCurves {
            var peak = 0.0
            for val in curve {
                peak = max(peak, val)
                if peak - val >= ddThreshold { ddCount += 1; break }
            }
        }
        let probDD = Double(ddCount) / Double(simulationCount)

        let medianIdx = simulationCount / 2
        let p5Idx = Int(Double(simulationCount - 1) * 0.05)
        let p95Idx = Int(Double(simulationCount - 1) * 0.95)

        return SimulationResult(
            bands: bands,
            probProfit: probProfit,
            probTarget: probTarget,
            probDrawdown20: probDD,
            medianFinalPnL: allFinals[medianIdx],
            worstCase: allFinals[p5Idx],
            bestCase: allFinals[p95Idx]
        )
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monte Carlo Simulation", systemImage: "dice.fill")
                .font(.cardTitle)

            if let result {
                // Confidence band chart
                Chart {
                    // Fill between 5th and 95th
                    ForEach(0..<result.bands[0].points.count, id: \.self) { idx in
                        AreaMark(
                            x: .value("Trade", idx),
                            yStart: .value("P5", result.bands[0].points[idx]),
                            yEnd: .value("P95", result.bands[4].points[idx])
                        )
                        .foregroundStyle(Color.accent.opacity(0.08))
                    }
                    // Fill between 25th and 75th
                    ForEach(0..<result.bands[1].points.count, id: \.self) { idx in
                        AreaMark(
                            x: .value("Trade", idx),
                            yStart: .value("P25", result.bands[1].points[idx]),
                            yEnd: .value("P75", result.bands[3].points[idx])
                        )
                        .foregroundStyle(Color.accent.opacity(0.15))
                    }
                    // Median line
                    ForEach(0..<result.bands[2].points.count, id: \.self) { idx in
                        LineMark(
                            x: .value("Trade", idx),
                            y: .value("Median", result.bands[2].points[idx])
                        )
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    // Zero line
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
                .chartXAxisLabel("Trade #")
                .chartYAxisLabel("P&L")
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                                    .font(.smallText)
                            }
                        }
                    }
                }
                .frame(height: 180)

                // Legend
                HStack(spacing: 12) {
                    legendItem("5th-95th", Color.accent.opacity(0.15))
                    legendItem("25th-75th", Color.accent.opacity(0.3))
                    legendItem("Median", Color.accent)
                }
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

                // Probability stats
                HStack(spacing: 0) {
                    probStat("Profitable", result.probProfit, Color.semanticGreen)
                    Divider().frame(height: 36)
                    probStat("Hit Target", result.probTarget, Color.semanticAmber)
                    Divider().frame(height: 36)
                    probStat("20% DD", result.probDrawdown20, Color.semanticRed)
                }

                // Outcome range
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.smallText)
                        .foregroundStyle(Color.accent)
                    Text("90% confidence: \(result.worstCase.asCompactCurrency) to \(result.bestCase.asCompactCurrency) over \(trades.count) trades")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("\(simulationCount) randomized simulations of your \(trades.count)-trade history")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Need at least 15 trades for simulation")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
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

    // MARK: - Subviews

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label)
        }
    }

    private func probStat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.0f%%", value * 100))
                .font(.monoSubtitle)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.monoSmall)
                .fontWeight(.medium)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
    }
}
