import SwiftUI
import Charts

/// Walk through trades chronologically with running equity curve and stats
struct TradeReplayView: View {
    let trades: [Trade]
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var playbackSpeed: Double = 1.0

    private var sortedTrades: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private var currentTrade: Trade? {
        guard currentIndex < sortedTrades.count else { return nil }
        return sortedTrades[currentIndex]
    }

    private var visibleTrades: [Trade] {
        Array(sortedTrades.prefix(currentIndex + 1))
    }

    private var runningPnL: Double {
        visibleTrades.reduce(0.0) { $0 + $1.profitDouble }
    }

    private var runningMetrics: (wins: Int, losses: Int, winRate: Double, streak: Int) {
        let wins = visibleTrades.filter(\.isWin).count
        let losses = visibleTrades.filter(\.isLoss).count
        let wr = visibleTrades.isEmpty ? 0 : Double(wins) / Double(visibleTrades.count) * 100

        // Current streak
        var streak = 0
        for trade in visibleTrades.reversed() {
            if trade.isWin {
                if streak >= 0 { streak += 1 } else { break }
            } else if trade.isLoss {
                if streak <= 0 { streak -= 1 } else { break }
            }
        }
        return (wins, losses, wr, streak)
    }

    private struct EquityPoint: Identifiable {
        let id: Int
        let tradeNumber: Int
        let cumulative: Double
    }

    private var equityCurve: [EquityPoint] {
        var cum = 0.0
        var points = [EquityPoint(id: -1, tradeNumber: 0, cumulative: 0)]
        for (i, trade) in visibleTrades.enumerated() {
            cum += trade.profitDouble
            points.append(EquityPoint(id: i, tradeNumber: i + 1, cumulative: cum))
        }
        return points
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Trade Replay")
                    .font(.kpiValueSecondary)
                    .fontWeight(.bold)
                Text("\(currentIndex + 1) / \(sortedTrades.count)")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left: Equity curve + controls
                VStack(spacing: 12) {
                    equityChart
                    controls
                    runningStatsBar
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: Current trade detail
                if let trade = currentTrade {
                    tradeCard(trade)
                        .frame(width: 260)
                }
            }
            .padding(16)
        }
        .frame(width: 800, height: 520)
    }

    // MARK: - Equity Chart

    private var equityChart: some View {
        Chart {
            ForEach(equityCurve) { point in
                LineMark(
                    x: .value("Trade #", point.tradeNumber),
                    y: .value("P&L", point.cumulative)
                )
                .foregroundStyle(Color.accent)

                AreaMark(
                    x: .value("Trade #", point.tradeNumber),
                    y: .value("P&L", point.cumulative)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accent.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Current position marker
            if let last = equityCurve.last {
                PointMark(
                    x: .value("Trade #", last.tradeNumber),
                    y: .value("P&L", last.cumulative)
                )
                .foregroundStyle(Color.forPnL(last.cumulative))
                .symbolSize(60)
            }

            // Zero line
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4]))
                .foregroundStyle(.secondary.opacity(0.3))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.asCompactCurrency)
                    }
                }
            }
        }
        .chartXAxisLabel("Trade #", alignment: .center)
        .frame(height: 200)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            // Rewind to start
            Button { currentIndex = 0; isPlaying = false } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)

            // Step back
            Button { stepBack() } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.plain)
            .disabled(currentIndex == 0)

            // Play/Pause
            Button { togglePlayback() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.cardTitle)
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= sortedTrades.count - 1)

            // Step forward
            Button { stepForward() } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= sortedTrades.count - 1)

            // Skip to end
            Button { currentIndex = sortedTrades.count - 1; isPlaying = false } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(currentIndex >= sortedTrades.count - 1)

            Spacer()

            // Speed control
            HStack(spacing: 4) {
                Text("Speed:")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Picker("", selection: $playbackSpeed) {
                    Text("0.5x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                    Text("5x").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Running Stats

    private var runningStatsBar: some View {
        let stats = runningMetrics
        return HStack(spacing: 20) {
            statPill("P&L", runningPnL.asCurrency, Color.forPnL(runningPnL))
            statPill("W/L", "\(stats.wins)/\(stats.losses)", .primary)
            statPill("Win Rate", String(format: "%.0f%%", stats.winRate), stats.winRate >= 50 ? Color.semanticGreen : Color.semanticRed)
            statPill("Streak", "\(stats.streak > 0 ? "+" : "")\(stats.streak)", Color.forPnL(Double(stats.streak)))
            Spacer()
        }
    }

    private func statPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Trade Card

    private func tradeCard(_ trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(trade.tickerDisplay)
                    .font(.cardTitle)
                    .fontWeight(.bold)
                Text(trade.directionSymbol)
                    .font(.cardTitle)
                    .foregroundStyle(trade.direction == .buy ? Color.semanticGreen : Color.semanticRed)
                Spacer()
                Text(trade.profitDouble.asCurrency)
                    .font(.cardTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.forPnL(trade.netProfit))
            }

            Divider()

            // Details grid
            VStack(spacing: 4) {
                detailRow("Session", trade.session.displayName)
                detailRow("Time", "\(trade.openTime.tradeDisplayString) ET")
                detailRow("Duration", "\(trade.durationMin) min")
                detailRow("Shares", String(format: "%.2f", trade.shares))
                detailRow("R-Multiple", trade.rMultiple.asRMultiple)
                detailRow("MAE", trade.maePoints.asPoints)
                detailRow("MFE", trade.mfePoints.asPoints)
            }

            Divider()

            // Context at this point in time
            VStack(alignment: .leading, spacing: 4) {
                Text("Running Context")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)

                let pctOfTotal = sortedTrades.isEmpty ? 0 : Double(currentIndex + 1) / Double(sortedTrades.count) * 100
                contextRow("Progress", String(format: "%.0f%% complete", pctOfTotal))

                let avgPnL = visibleTrades.isEmpty ? 0 : runningPnL / Double(visibleTrades.count)
                contextRow("Avg P&L/Trade", avgPnL.asCurrency)

                // Peak and drawdown
                let (peak, currentDD) = calculatePeakAndDD()
                contextRow("Peak P&L", peak.asCurrency)
                if currentDD > 0 {
                    contextRow("Current DD", (-currentDD).asCurrency)
                }
            }

            Spacer()

            // Trade verdict
            HStack {
                Image(systemName: trade.isWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(trade.isWin ? Color.semanticGreen : Color.semanticRed)
                Text(trade.isWin ? "Winner" : "Loser")
                    .font(.smallText)
                    .fontWeight(.medium)
                    .foregroundStyle(trade.isWin ? Color.semanticGreen : Color.semanticRed)
                Spacer()
                if !trade.tagList.isEmpty {
                    Text(trade.tagList.joined(separator: ", "))
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
   .overlay(
       RoundedRectangle(cornerRadius: 12)
           .stroke(Color.borderCard, lineWidth: 1)
   )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.monoSubtitle)
        }
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Logic

    private func stepForward() {
        guard currentIndex < sortedTrades.count - 1 else {
            isPlaying = false
            return
        }
        currentIndex += 1
    }

    private func stepBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard isPlaying else { return }
        guard currentIndex < sortedTrades.count - 1 else {
            isPlaying = false
            return
        }

        let delay = 1.0 / playbackSpeed
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard isPlaying else { return }
            stepForward()
            if currentIndex >= sortedTrades.count - 1 {
                isPlaying = false
            } else {
                startPlayback()
            }
        }
    }

    private func calculatePeakAndDD() -> (peak: Double, currentDD: Double) {
        var peak = 0.0, cum = 0.0
        for trade in visibleTrades {
            cum += trade.profitDouble
            peak = max(peak, cum)
        }
        return (peak, peak - cum)
    }
}
