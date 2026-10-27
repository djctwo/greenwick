import SwiftUI

/// Institutional-grade execution analysis — slippage by time/symbol, fill quality, execution score
struct ExecutionQuality: View {
    let trades: [Trade]

    // MARK: - Data Models

    private struct HourSlippage: Identifiable {
        let id: Int // hour
        let hour: Int
        let avgSlippage: Double
        let tradeCount: Int
    }

    private struct SymbolSlippage: Identifiable {
        let id: String
        let symbol: String
        let tradeCount: Int
        let avgSlippage: Double
        let estimatedCost: Double
    }

    // MARK: - Computed Data

    private var tradesWithSlippage: [Trade] {
        trades.filter { $0.slippagePoints > 0 }
    }

    private var hourlySlippage: [HourSlippage] {
        let grouped = Dictionary(grouping: tradesWithSlippage) { $0.hour }
        return grouped.map { hour, hourTrades in
            let avg = hourTrades.map(\.slippagePoints).reduce(0, +) / Double(hourTrades.count)
            return HourSlippage(id: hour, hour: hour, avgSlippage: avg, tradeCount: hourTrades.count)
        }
        .sorted { $0.hour < $1.hour }
    }

    private var worstHour: HourSlippage? {
        hourlySlippage.max(by: { $0.avgSlippage < $1.avgSlippage })
    }

    private var symbolSlippage: [SymbolSlippage] {
        let grouped = Dictionary(grouping: tradesWithSlippage) { $0.symbol }
        return grouped.map { symbol, symbolTrades in
            let avgSlip = symbolTrades.map(\.slippagePoints).reduce(0, +) / Double(symbolTrades.count)
            let avgShares = symbolTrades.map(\.shares).reduce(0, +) / Double(symbolTrades.count)
            let cost = avgSlip * avgShares
            return SymbolSlippage(
                id: symbol,
                symbol: symbol,
                tradeCount: symbolTrades.count,
                avgSlippage: avgSlip,
                estimatedCost: cost
            )
        }
        .sorted { $0.avgSlippage > $1.avgSlippage }
        .prefix(5)
        .map { $0 }
    }

    // MARK: - Execution Score

    private var executionScore: Double {
        guard !trades.isEmpty else { return 0 }

        // Slippage score (weight 40%): lower avg slippage = higher score
        let allSlippages = trades.map(\.slippagePoints)
        let avgSlip = allSlippages.reduce(0, +) / Double(allSlippages.count)
        // 0 pts slippage = 100, 3+ pts = 0
        let slippageScore = max(0, min(100, (1 - avgSlip / 3.0) * 100))

        // Consistency score (weight 30%): low std dev of slippage
        let mean = avgSlip
        let variance = allSlippages.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(allSlippages.count)
        let stdDev = variance.squareRoot()
        // std dev 0 = 100, 2+ = 0
        let consistencyScore = max(0, min(100, (1 - stdDev / 2.0) * 100))

        // Exit efficiency score (weight 30%)
        let efficiencies = trades.compactMap(\.exitEfficiency)
        let avgEfficiency: Double
        if efficiencies.isEmpty {
            avgEfficiency = 50 // neutral if no data
        } else {
            avgEfficiency = efficiencies.reduce(0, +) / Double(efficiencies.count)
        }

        return slippageScore * 0.4 + consistencyScore * 0.3 + avgEfficiency * 0.3
    }

    private var scoreColor: Color {
        if executionScore > 70 { return .semanticGreen }
        if executionScore >= 40 { return .semanticAmber }
        return .semanticRed
    }

    private var scoreLabel: String {
        if executionScore > 70 { return "Good" }
        if executionScore >= 40 { return "Fair" }
        return "Poor"
    }

    // MARK: - Chart Helpers

    private var maxHourlySlippage: Double {
        hourlySlippage.map(\.avgSlippage).max() ?? 1
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Execution Quality", systemImage: "gauge.with.dots.needle.33percent")
                .font(.cardTitle)

            if trades.count < 10 {
                Text("Need at least 10 trades for execution analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if tradesWithSlippage.isEmpty {
                Text("No slippage data available")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                slippageByHourSection
                slippageBySymbolSection
                executionScoreSection
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

    // MARK: - Slippage by Time of Day

    private var slippageByHourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLIPPAGE BY TIME OF DAY")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            // Custom bar chart using rectangles
            GeometryReader { geo in
                let barCount = hourlySlippage.count
                let spacing: CGFloat = 2
                let barWidth = barCount > 0
                    ? max(4, (geo.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
                    : 4

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(hourlySlippage) { item in
                        VStack(spacing: 2) {
                            // Bar
                            let normalizedHeight = maxHourlySlippage > 0
                                ? CGFloat(item.avgSlippage / maxHourlySlippage)
                                : 0
                            let barHeight = max(2, normalizedHeight * (geo.size.height - 20))

                            RoundedRectangle(cornerRadius: 2)
                                .fill(barColor(for: item.avgSlippage))
                                .frame(width: barWidth, height: barHeight)

                            // Hour label
                            Text("\(item.hour)")
                                .font(.monoSmall)
                                .foregroundStyle(Color.textTertiary)
                                .frame(height: 14)
                        }
                    }
                }
            }
            .frame(height: 100)

            // Worst hour callout
            if let worst = worstHour {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                    Text("Worst fills at \(worst.hour):00 -- avg \(String(format: "%.1f", worst.avgSlippage)) pts slippage (\(worst.tradeCount) trades)")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func barColor(for slippage: Double) -> Color {
        if slippage < 0.5 { return .semanticGreen.opacity(0.7) }
        if slippage < 1.5 { return .semanticAmber.opacity(0.7) }
        return .semanticRed.opacity(0.7)
    }

    // MARK: - Slippage by Symbol

    private var slippageBySymbolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLIPPAGE BY SYMBOL")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            // Header row
            HStack(spacing: 0) {
                tableHeader("Symbol", width: 80, alignment: .leading)
                tableHeader("Trades", width: 56)
                tableHeader("Avg Slip", width: 64)
                tableHeader("Cost ($)", width: 72)
            }
            .padding(.vertical, 4)
            .background(Color.bgContent)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Data rows
            ForEach(Array(symbolSlippage.enumerated()), id: \.element.id) { idx, item in
                HStack(spacing: 0) {
                    Text(item.symbol)
                        .foregroundStyle(Color.forTicker(item.symbol))
                        .frame(width: 80, alignment: .leading)
                    Text("\(item.tradeCount)")
                        .frame(width: 56)
                    Text(String(format: "%.1f pts", item.avgSlippage))
                        .foregroundStyle(slippageValueColor(item.avgSlippage))
                        .frame(width: 64)
                    Text(item.estimatedCost.asCurrency)
                        .foregroundStyle(Color.semanticRed)
                        .frame(width: 72)
                }
                .font(.monoSubtitle)

                if idx < symbolSlippage.count - 1 {
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func tableHeader(_ title: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(title.uppercased())
            .font(.monoSmall)
            .foregroundStyle(Color.textSecondary)
            .tracking(0.3)
            .frame(width: width, alignment: alignment)
    }

    private func slippageValueColor(_ value: Double) -> Color {
        if value < 0.5 { return .semanticGreen }
        if value < 1.5 { return .semanticAmber }
        return .semanticRed
    }

    // MARK: - Execution Score

    private var executionScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXECUTION SCORE")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            HStack(spacing: 16) {
                // Score gauge
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.borderCard, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: 0.75 * executionScore / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: 80, height: 80)

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", executionScore))
                            .font(.kpiValueSecondary)
                            .fontWeight(.bold)
                            .foregroundStyle(scoreColor)
                        Text(scoreLabel)
                            .font(.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Score breakdown
                VStack(alignment: .leading, spacing: 6) {
                    scoreRow("Low Slippage", weight: "40%")
                    scoreRow("Fill Consistency", weight: "30%")
                    scoreRow("Exit Efficiency", weight: "30%")
                }
            }
        }
    }

    private func scoreRow(_ label: String, weight: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(weight)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
