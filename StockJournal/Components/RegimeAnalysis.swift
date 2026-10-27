import SwiftUI

/// Detects market regime changes and shows how performance varies by regime
struct RegimeAnalysis: View {
    let trades: [Trade]

    // MARK: - Regime Types

    private enum Regime: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case choppy = "Choppy"
        case volatile = "Volatile"
        case calm = "Calm"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .trending: "arrow.up.right"
            case .choppy: "waveform"
            case .volatile: "bolt.fill"
            case .calm: "leaf.fill"
            }
        }

        var color: Color {
            switch self {
            case .trending: .semanticGreen
            case .choppy: .semanticRed
            case .volatile: .semanticAmber
            case .calm: .semanticBlue
            }
        }
    }

    // MARK: - Data Models

    private struct DayData: Identifiable {
        let id: String // date string
        let date: Date
        let trades: [Trade]
        let winRate: Double
        let avgPnL: Double
        let totalPnL: Double
        let avgMAE: Double
        let avgWinner: Double
        let avgLoser: Double
        let regime: Regime
    }

    private struct RegimeStats: Identifiable {
        let id: String
        let regime: Regime
        let dayCount: Int
        let winRate: Double
        let avgPnL: Double
        let totalPnL: Double
    }

    // MARK: - Computed Data

    /// Pre-compute median MAE per day from raw trades (avoids recursive cycle with tradingDays)
    private var medianDayMAE: Double {
        let grouped = Dictionary(grouping: trades) { trade in
            TradingCalendar.dayKey(trade.closeTime)
        }
        let dayMAEs = grouped.values.compactMap { dayTrades -> Double? in
            guard !dayTrades.isEmpty else { return nil }
            return dayTrades.map(\.maePoints).reduce(0, +) / Double(dayTrades.count)
        }.sorted()
        guard !dayMAEs.isEmpty else { return 0 }
        let mid = dayMAEs.count / 2
        return dayMAEs.count % 2 == 0
            ? (dayMAEs[mid - 1] + dayMAEs[mid]) / 2
            : dayMAEs[mid]
    }

    /// One entry per US trading day (New York date of the close)
    private var tradingDays: [DayData] {
        let grouped = Dictionary(grouping: trades) { trade in
            TradingCalendar.dayKey(trade.closeTime)
        }
        let median = medianDayMAE

        return grouped.compactMap { dateStr, dayTrades in
            guard !dayTrades.isEmpty else { return nil }
            guard let date = TradingCalendar.date(fromDayKey: dateStr) else { return nil }

            let winners = dayTrades.filter(\.isWin)
            let losers = dayTrades.filter(\.isLoss)
            let winRate = Double(winners.count) / Double(dayTrades.count) * 100
            let totalPnL = dayTrades.map(\.profitDouble).reduce(0, +)
            let avgPnL = totalPnL / Double(dayTrades.count)
            let avgMAE = dayTrades.map(\.maePoints).reduce(0, +) / Double(dayTrades.count)
            let avgWinner = winners.isEmpty ? 0 : winners.map(\.profitDouble).reduce(0, +) / Double(winners.count)
            let avgLoser = losers.isEmpty ? 0 : abs(losers.map(\.profitDouble).reduce(0, +) / Double(losers.count))

            let regime = Self.classifyRegime(
                winRate: winRate,
                avgWinner: avgWinner,
                avgLoser: avgLoser,
                avgMAE: avgMAE,
                medianMAE: median
            )

            return DayData(
                id: dateStr,
                date: date,
                trades: dayTrades,
                winRate: winRate,
                avgPnL: avgPnL,
                totalPnL: totalPnL,
                avgMAE: avgMAE,
                avgWinner: avgWinner,
                avgLoser: avgLoser,
                regime: regime
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func classifyRegime(winRate: Double, avgWinner: Double, avgLoser: Double, avgMAE: Double, medianMAE: Double) -> Regime {
        // Trending: high win rate AND winners significantly larger than losers
        if winRate > 60 && avgLoser > 0 && avgWinner > 1.5 * avgLoser {
            return .trending
        }
        // Choppy: low win rate
        if winRate < 40 {
            return .choppy
        }
        // Volatile: high MAE relative to median
        if medianMAE > 0 && avgMAE > 2 * medianMAE {
            return .volatile
        }
        // Calm: everything else
        return .calm
    }

    private var regimeStats: [RegimeStats] {
        let grouped = Dictionary(grouping: tradingDays) { $0.regime }
        return Regime.allCases.compactMap { regime in
            guard let days = grouped[regime], !days.isEmpty else { return nil }

            let allTrades = days.flatMap(\.trades)
            let totalWins = allTrades.filter(\.isWin).count
            let winRate = allTrades.isEmpty ? 0 : Double(totalWins) / Double(allTrades.count) * 100
            let totalPnL = days.map(\.totalPnL).reduce(0, +)
            let avgPnL = totalPnL / Double(days.count)

            return RegimeStats(
                id: regime.rawValue,
                regime: regime,
                dayCount: days.count,
                winRate: winRate,
                avgPnL: avgPnL,
                totalPnL: totalPnL
            )
        }
    }

    private var bestRegime: RegimeStats? {
        regimeStats.max(by: { $0.avgPnL < $1.avgPnL })
    }

    private var worstRegime: RegimeStats? {
        regimeStats.min(by: { $0.totalPnL < $1.totalPnL })
    }

    private var currentRegime: Regime? {
        let recent = tradingDays.suffix(5)
        guard !recent.isEmpty else { return nil }

        // Mode of recent 5 days
        var counts: [Regime: Int] = [:]
        for day in recent {
            counts[day.regime, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Chart Helpers

    private var maxRegimeDays: Int {
        regimeStats.map(\.dayCount).max() ?? 1
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Market Regime", systemImage: "waveform.path.ecg")
                .font(.cardTitle)

            if trades.count < 10 {
                Text("Need at least 10 trades for regime analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if tradingDays.count < 3 {
                Text("Need at least 3 trading days for regime classification")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                currentRegimeIndicator
                regimeDistributionChart
                regimePerformanceTable
                regimeInsights
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

    // MARK: - Current Regime Indicator

    private var currentRegimeIndicator: some View {
        Group {
            if let regime = currentRegime {
                HStack(spacing: 8) {
                    Circle()
                        .fill(regime.color)
                        .frame(width: 8, height: 8)

                    Image(systemName: regime.icon)
                        .font(.smallText)
                        .foregroundStyle(regime.color)

                    Text("Current Regime:")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)

                    Text(regime.rawValue)
                        .font(.monoSubtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(regime.color)

                    Text("(last 5 trading days)")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(regime.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(regime.color.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Regime Distribution Chart

    private var regimeDistributionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REGIME DISTRIBUTION")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            VStack(spacing: 6) {
                ForEach(regimeStats) { stat in
                    HStack(spacing: 8) {
                        // Regime label
                        HStack(spacing: 4) {
                            Image(systemName: stat.regime.icon)
                                .font(.monoSmall)
                                .foregroundStyle(stat.regime.color)
                            Text(stat.regime.rawValue)
                                .font(.smallText)
                                .foregroundStyle(Color.textPrimary)
                        }
                        .frame(width: 80, alignment: .leading)

                        // Horizontal bar
                        GeometryReader { geo in
                            let ratio = maxRegimeDays > 0
                                ? CGFloat(stat.dayCount) / CGFloat(maxRegimeDays)
                                : 0
                            let barWidth = max(2, ratio * geo.size.width)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(stat.regime.color.opacity(0.6))
                                .frame(width: barWidth, height: 16)
                        }
                        .frame(height: 16)

                        // Day count
                        Text("\(stat.dayCount)d")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Performance Table

    private var regimePerformanceTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERFORMANCE BY REGIME")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            // Header row
            HStack(spacing: 0) {
                tableHeader("Regime", width: 72, alignment: .leading)
                tableHeader("Days", width: 44)
                tableHeader("Win Rate", width: 64)
                tableHeader("Avg P&L", width: 72)
                tableHeader("Total P&L", width: 80)
            }
            .padding(.vertical, 4)
            .background(Color.bgContent)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Data rows
            ForEach(Array(regimeStats.enumerated()), id: \.element.id) { idx, stat in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stat.regime.color)
                            .frame(width: 6, height: 6)
                        Text(stat.regime.rawValue)
                            .foregroundStyle(stat.regime.color)
                    }
                    .frame(width: 72, alignment: .leading)

                    Text("\(stat.dayCount)")
                        .frame(width: 44)

                    Text(String(format: "%.0f%%", stat.winRate))
                        .foregroundStyle(stat.winRate >= 50 ? Color.semanticGreen : Color.semanticRed)
                        .frame(width: 64)

                    Text(stat.avgPnL.asCurrency)
                        .foregroundStyle(Color.forPnL(stat.avgPnL))
                        .frame(width: 72)

                    Text(stat.totalPnL.asCompactCurrency)
                        .foregroundStyle(Color.forPnL(stat.totalPnL))
                        .frame(width: 80)
                }
                .font(.monoSubtitle)

                if idx < regimeStats.count - 1 {
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

    // MARK: - Insights

    private var regimeInsights: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let best = bestRegime, best.avgPnL > 0 {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticGreen)
                    Text("You thrive in \(best.regime.rawValue) days -- avg \(best.avgPnL.asCurrency)/day across \(best.dayCount) days")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if let worst = worstRegime, worst.totalPnL < 0 {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                    Text("Consider sitting out \(worst.regime.rawValue) days -- costs you \(abs(worst.totalPnL).asCurrency) total")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if regimeStats.count <= 1 {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticBlue)
                    Text("More trading days needed to detect varied market regimes")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
