import SwiftUI
import Charts

/// Comprehensive drawdown analysis — time underwater chart, drawdown event table,
/// summary statistics, and recovery phase comparison
struct DrawdownRecovery: View {
    let trades: [Trade]

    // MARK: - Data Models

    private struct EquityPoint: Identifiable {
        let id: Int // trade index
        let tradeNumber: Int
        let date: Date
        let drawdownDollar: Double  // negative or zero
        let drawdownPercent: Double // negative or zero
    }

    private struct DrawdownEvent: Identifiable {
        let id = UUID()
        let startIndex: Int
        let endIndex: Int  // index where new high reached (or last trade if unrecovered)
        let troughIndex: Int
        let depthDollar: Double   // max drawdown amount (positive value)
        let depthPercent: Double  // max drawdown percentage (positive value)
        let peakAtStart: Double   // equity peak before drawdown began
        let duration: Int         // trades from peak to recovery
        let recoveryTrades: Int   // trades from trough to new high (0 if unrecovered)
        let startDate: Date
        let endDate: Date
        let troughDate: Date
        let isRecovered: Bool
    }

    private struct PhaseStats {
        let avgShareSize: Double
        let winRate: Double
        let tradeCount: Int
        let symbolBreakdown: [(symbol: String, count: Int)]
        let sessionBreakdown: [(session: MarketSession, count: Int)]
    }

    // MARK: - Computed Data

    private var sortedTrades: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private var equityCurve: [EquityPoint] {
        let sorted = sortedTrades
        guard sorted.count >= 20 else { return [] }

        var cumulative = 0.0
        var peak = 0.0
        var points: [EquityPoint] = []

        for (idx, trade) in sorted.enumerated() {
            cumulative += trade.profitDouble
            peak = max(peak, cumulative)
            let ddDollar = cumulative - peak // zero or negative
            let ddPercent = peak > 0 ? (ddDollar / peak) * 100 : 0

            points.append(EquityPoint(
                id: idx,
                tradeNumber: idx + 1,
                date: trade.closeTime,
                drawdownDollar: ddDollar,
                drawdownPercent: ddPercent
            ))
        }
        return points
    }

    private var drawdownEvents: [DrawdownEvent] {
        let sorted = sortedTrades
        guard sorted.count >= 20 else { return [] }

        var cumulative = 0.0
        var peak = 0.0
        var events: [DrawdownEvent] = []

        var inDrawdown = false
        var ddStartIdx = 0
        var ddTroughIdx = 0
        var ddMaxDepth = 0.0
        var ddPeakAtStart = 0.0

        for (idx, trade) in sorted.enumerated() {
            cumulative += trade.profitDouble

            if cumulative >= peak {
                // New high reached
                if inDrawdown {
                    // Close the drawdown event
                    let ddPercent = ddPeakAtStart > 0 ? (ddMaxDepth / ddPeakAtStart) * 100 : 0
                    events.append(DrawdownEvent(
                        startIndex: ddStartIdx,
                        endIndex: idx,
                        troughIndex: ddTroughIdx,
                        depthDollar: ddMaxDepth,
                        depthPercent: ddPercent,
                        peakAtStart: ddPeakAtStart,
                        duration: idx - ddStartIdx,
                        recoveryTrades: idx - ddTroughIdx,
                        startDate: sorted[ddStartIdx].closeTime,
                        endDate: sorted[idx].closeTime,
                        troughDate: sorted[ddTroughIdx].closeTime,
                        isRecovered: true
                    ))
                    inDrawdown = false
                }
                peak = cumulative
            } else {
                // In drawdown
                let currentDD = peak - cumulative
                if !inDrawdown {
                    inDrawdown = true
                    ddStartIdx = idx
                    ddTroughIdx = idx
                    ddMaxDepth = currentDD
                    ddPeakAtStart = peak
                }
                if currentDD > ddMaxDepth {
                    ddMaxDepth = currentDD
                    ddTroughIdx = idx
                }
            }
        }

        // Close any open drawdown
        if inDrawdown {
            let lastIdx = sorted.count - 1
            let ddPercent = ddPeakAtStart > 0 ? (ddMaxDepth / ddPeakAtStart) * 100 : 0
            events.append(DrawdownEvent(
                startIndex: ddStartIdx,
                endIndex: lastIdx,
                troughIndex: ddTroughIdx,
                depthDollar: ddMaxDepth,
                depthPercent: ddPercent,
                peakAtStart: ddPeakAtStart,
                duration: lastIdx - ddStartIdx + 1,
                recoveryTrades: 0,
                startDate: sorted[ddStartIdx].closeTime,
                endDate: sorted[lastIdx].closeTime,
                troughDate: sorted[ddTroughIdx].closeTime,
                isRecovered: false
            ))
        }

        return events
    }

    // MARK: - Summary Stats

    private var avgRecoveryTrades: Double {
        let recovered = drawdownEvents.filter(\.isRecovered)
        guard !recovered.isEmpty else { return 0 }
        return Double(recovered.map(\.recoveryTrades).reduce(0, +)) / Double(recovered.count)
    }

    private var deepestEvent: DrawdownEvent? {
        drawdownEvents.max(by: { $0.depthDollar < $1.depthDollar })
    }

    private var longestEvent: DrawdownEvent? {
        drawdownEvents.max(by: { $0.duration < $1.duration })
    }

    private var isCurrentlyInDrawdown: Bool {
        guard let last = drawdownEvents.last else { return false }
        return !last.isRecovered
    }

    private var percentTimeInDrawdown: Double {
        guard !equityCurve.isEmpty else { return 0 }
        let inDD = equityCurve.filter { $0.drawdownDollar < 0 }.count
        return Double(inDD) / Double(equityCurve.count) * 100
    }

    // MARK: - Recovery Analysis

    private var drawdownPhaseStats: PhaseStats {
        computePhaseStats(for: drawdownPhaseTrades)
    }

    private var recoveryPhaseStats: PhaseStats {
        computePhaseStats(for: recoveryPhaseTrades)
    }

    private var drawdownPhaseTrades: [Trade] {
        let sorted = sortedTrades
        var result: [Trade] = []
        for event in drawdownEvents {
            let start = event.startIndex
            let end = min(event.troughIndex, sorted.count - 1)
            if start <= end {
                result.append(contentsOf: sorted[start...end])
            }
        }
        return result
    }

    private var recoveryPhaseTrades: [Trade] {
        let sorted = sortedTrades
        var result: [Trade] = []
        for event in drawdownEvents where event.isRecovered {
            let start = event.troughIndex + 1
            let end = event.endIndex
            if start <= end, start < sorted.count, end < sorted.count {
                result.append(contentsOf: sorted[start...end])
            }
        }
        return result
    }

    private func computePhaseStats(for phaseTrades: [Trade]) -> PhaseStats {
        guard !phaseTrades.isEmpty else {
            return PhaseStats(avgShareSize: 0, winRate: 0, tradeCount: 0, symbolBreakdown: [], sessionBreakdown: [])
        }

        let avgShares = phaseTrades.map(\.shares).reduce(0, +) / Double(phaseTrades.count)
        let wr = Double(phaseTrades.filter(\.isWin).count) / Double(phaseTrades.count) * 100

        var symbolCounts: [String: Int] = [:]
        var sessionCounts: [MarketSession: Int] = [:]
        for trade in phaseTrades {
            symbolCounts[trade.symbol, default: 0] += 1
            sessionCounts[trade.session, default: 0] += 1
        }

        let symbols = symbolCounts.sorted { $0.value > $1.value }.map { (symbol: $0.key, count: $0.value) }
        let sessions = sessionCounts.sorted { $0.value > $1.value }.map { (session: $0.key, count: $0.value) }

        return PhaseStats(avgShareSize: avgShares, winRate: wr, tradeCount: phaseTrades.count, symbolBreakdown: symbols, sessionBreakdown: sessions)
    }

    // MARK: - Date Formatting

    private static let shortDateFormatter: DateFormatter = TradingCalendar.formatter("MMM d") // trading-day dates (ET)

    private static let medDateFormatter: DateFormatter = TradingCalendar.formatter("MMM d, yyyy") // trading-day dates (ET)

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Drawdown Recovery Analysis", systemImage: "chart.line.downtrend.xyaxis")
                .font(.cardTitle)

            if trades.count < 20 {
                Text("Need at least 20 trades for drawdown analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if drawdownEvents.isEmpty {
                noDrawdownView
            } else {
                underwaterChart
                summaryStatsSection
                drawdownEventsTable
                recoveryAnalysisSection
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

    // MARK: - No Drawdowns

    private var noDrawdownView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.semanticGreen)
            Text("No drawdowns detected -- equity has only made new highs")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Time Underwater Chart

    private var underwaterChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIME UNDERWATER")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            Chart {
                ForEach(equityCurve) { point in
                    AreaMark(
                        x: .value("Trade", point.tradeNumber),
                        yStart: .value("Drawdown", point.drawdownDollar),
                        yEnd: .value("Zero", 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.semanticRed.opacity(0.6), Color.semanticRed.opacity(0.1)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )

                    LineMark(
                        x: .value("Trade", point.tradeNumber),
                        y: .value("Drawdown", point.drawdownDollar)
                    )
                    .foregroundStyle(Color.semanticRed.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }

                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4]))
            }
            .chartXAxisLabel("Trade #")
            .chartYAxisLabel("Drawdown ($)")
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
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.smallText)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Summary Stats

    private var summaryStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            HStack(spacing: 0) {
                summaryStatCell(
                    "Avg Recovery",
                    String(format: "%.1f trades", avgRecoveryTrades),
                    Color.accent
                )
                Divider().frame(height: 36)

                summaryStatCell(
                    "Deepest DD",
                    deepestEvent.map { "-\($0.depthDollar.asCurrency)" } ?? "--",
                    Color.semanticRed
                )
                Divider().frame(height: 36)

                summaryStatCell(
                    "Longest DD",
                    longestEvent.map { "\($0.duration) trades" } ?? "--",
                    Color.semanticAmber
                )
                Divider().frame(height: 36)

                summaryStatCell(
                    "% Underwater",
                    String(format: "%.0f%%", percentTimeInDrawdown),
                    percentTimeInDrawdown > 60 ? Color.semanticRed : Color.semanticGreen
                )
            }

            // Current status
            currentStatusBadge
        }
    }

    private func summaryStatCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
    }

    private var currentStatusBadge: some View {
        Group {
            if isCurrentlyInDrawdown, let current = drawdownEvents.last {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.semanticRed)
                        .frame(width: 6, height: 6)
                    Text("In drawdown: \(current.duration) trades, -\(current.depthDollar.asCurrency)")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticRed)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.semanticRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.semanticGreen)
                        .frame(width: 6, height: 6)
                    Text("At new equity high")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.semanticGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            }
        }
    }

    // MARK: - Drawdown Events Table

    private var drawdownEventsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRAWDOWN EVENTS")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            // Header row
            HStack(spacing: 0) {
                tableHeader("#", width: 24)
                tableHeader("Depth ($)", width: 72)
                tableHeader("Depth (%)", width: 62)
                tableHeader("Duration", width: 62)
                tableHeader("Recovery", width: 62)
                tableHeader("Start", width: 62)
                tableHeader("End", width: 62)
            }
            .padding(.vertical, 4)
            .background(Color.bgContent)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Event rows — show top 10 by depth
            let topEvents = drawdownEvents
                .sorted { $0.depthDollar > $1.depthDollar }
                .prefix(10)

            ForEach(Array(topEvents.enumerated()), id: \.element.id) { idx, event in
                HStack(spacing: 0) {
                    Text("\(idx + 1)")
                        .frame(width: 24)
                    Text("-\(event.depthDollar.asCurrency)")
                        .foregroundStyle(Color.semanticRed)
                        .frame(width: 72)
                    Text(String(format: "-%.1f%%", event.depthPercent))
                        .foregroundStyle(Color.semanticRed)
                        .frame(width: 62)
                    Text("\(event.duration)")
                        .frame(width: 62)
                    Text(event.isRecovered ? "\(event.recoveryTrades)" : "--")
                        .foregroundStyle(event.isRecovered ? Color.semanticGreen : Color.textSecondary)
                        .frame(width: 62)
                    Text(Self.shortDateFormatter.string(from: event.startDate))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 62)
                    Text(Self.shortDateFormatter.string(from: event.endDate))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 62)
                }
                .font(.monoSubtitle)

                if idx < topEvents.count - 1 {
                    Divider().opacity(0.3)
                }
            }

            if drawdownEvents.count > 10 {
                Text("+\(drawdownEvents.count - 10) more events")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func tableHeader(_ title: String, width: CGFloat) -> some View {
        Text(title.uppercased())
            .font(.monoSmall)
            .foregroundStyle(Color.textSecondary)
            .tracking(0.3)
            .frame(width: width)
    }

    // MARK: - Recovery Analysis

    private var recoveryAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOVERY ANALYSIS")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.smallText)
                    .foregroundStyle(Color.accent)
                Text("What changed during recoveries?")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .italic()
            }

            let ddStats = drawdownPhaseStats
            let recStats = recoveryPhaseStats

            if ddStats.tradeCount > 0 && recStats.tradeCount > 0 {
                HStack(spacing: 16) {
                    phaseColumn("Drawdown", ddStats, Color.semanticRed)
                    Divider()
                    phaseColumn("Recovery", recStats, Color.semanticGreen)
                }

                // Insight callout
                recoveryInsight(ddStats: ddStats, recStats: recStats)
            } else {
                Text("Not enough drawdown/recovery data for comparison")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func phaseColumn(_ title: String, _ stats: PhaseStats, _ accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.monoSmall)
                .foregroundStyle(accentColor)
                .tracking(0.3)

            phaseRow("Trades", "\(stats.tradeCount)")
            phaseRow("Win Rate", String(format: "%.1f%%", stats.winRate))
            phaseRow("Avg Shares", String(format: "%.0f", stats.avgShareSize))

            if let topSymbol = stats.symbolBreakdown.first {
                phaseRow("Top Symbol", topSymbol.symbol)
            }

            if let topSession = stats.sessionBreakdown.first {
                phaseRow("Top Session", topSession.session.displayName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func phaseRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
        }
    }

    private func recoveryInsight(ddStats: PhaseStats, recStats: PhaseStats) -> some View {
        let insights = buildInsights(ddStats: ddStats, recStats: recStats)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.monoSmall)
                        .foregroundStyle(Color.semanticAmber)
                    Text(insight)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func buildInsights(ddStats: PhaseStats, recStats: PhaseStats) -> [String] {
        var insights: [String] = []

        // Win rate comparison
        let wrDiff = recStats.winRate - ddStats.winRate
        if abs(wrDiff) > 5 {
            if wrDiff > 0 {
                insights.append("Win rate improves by \(String(format: "%.0f", wrDiff))pp during recoveries")
            } else {
                insights.append("Win rate drops by \(String(format: "%.0f", abs(wrDiff)))pp during recoveries -- may be forcing trades")
            }
        }

        // Position size comparison
        if ddStats.avgShareSize > 0 && recStats.avgShareSize > 0 {
            let sizeRatio = recStats.avgShareSize / ddStats.avgShareSize
            if sizeRatio < 0.8 {
                insights.append("Position sizes reduce during recovery — disciplined risk management")
            } else if sizeRatio > 1.3 {
                insights.append("Position sizes increase during recovery — possible revenge trading pattern")
            }
        }

        // Session shift
        if let ddTop = ddStats.sessionBreakdown.first,
           let recTop = recStats.sessionBreakdown.first,
           ddTop.session != recTop.session {
            insights.append("Session shift: \(ddTop.session.displayName) during drawdowns, \(recTop.session.displayName) during recoveries")
        }

        // Symbol shift
        if let ddTop = ddStats.symbolBreakdown.first,
           let recTop = recStats.symbolBreakdown.first,
           ddTop.symbol != recTop.symbol {
            insights.append("Symbol shift: \(ddTop.symbol) during drawdowns, \(recTop.symbol) during recoveries")
        }

        if insights.isEmpty {
            insights.append("Behavior is consistent between drawdown and recovery phases")
        }

        return insights
    }
}
