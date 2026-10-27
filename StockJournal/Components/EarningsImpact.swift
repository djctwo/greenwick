import SwiftUI

/// Analyzes how the trader performs around high-volatility catalyst days
/// (earnings, news events, sector moves) using a volatility-based heuristic.
///
/// Detects catalyst days per symbol where the trade's range or MAE exceeds 2x
/// that symbol's average, then compares catalyst-day vs normal-day performance.
struct EarningsImpact: View {
    let trades: [Trade]

    // MARK: - Analysis Models

    private struct CatalystAnalysis {
        let catalystTrades: [Trade]
        let normalTrades: [Trade]
        let heldThroughTrades: [Trade]  // entered before catalyst, closed after
    }

    private struct GroupStats {
        let count: Int
        let winRate: Double
        let avgPnL: Double
        let totalPnL: Double

        static let empty = GroupStats(count: 0, winRate: 0, avgPnL: 0, totalPnL: 0)

        static func from(_ trades: [Trade]) -> GroupStats {
            guard !trades.isEmpty else { return .empty }
            let wins = trades.filter(\.isWin).count
            let total = trades.map(\.profitDouble).reduce(0, +)
            return GroupStats(
                count: trades.count,
                winRate: Double(wins) / Double(trades.count),
                avgPnL: total / Double(trades.count),
                totalPnL: total
            )
        }
    }

    // MARK: - Computed

    private var analysis: CatalystAnalysis {
        let bySymbol = Dictionary(grouping: trades, by: \.symbol)

        // Compute per-symbol volatility thresholds
        var catalystDates: [String: Set<String>] = [:]  // symbol -> set of date strings
        for (symbol, symbolTrades) in bySymbol {
            let volatilities = symbolTrades.map { max($0.maePoints, $0.rangeSize) }
            let avgVol = volatilities.isEmpty ? 0 : volatilities.reduce(0, +) / Double(volatilities.count)
            let threshold = avgVol * 2.0

            guard threshold > 0 else { continue }

            var dates = Set<String>()
            for trade in symbolTrades {
                let vol = max(trade.maePoints, trade.rangeSize)
                if vol >= threshold {
                    dates.insert(TradingCalendar.dayKey(trade.closeTime))
                }
            }
            catalystDates[symbol] = dates
        }

        // Classify trades
        var catalystTrades: [Trade] = []
        var normalTrades: [Trade] = []
        var heldThroughTrades: [Trade] = []

        for trade in trades {
            let tradeDate = TradingCalendar.dayKey(trade.closeTime)
            let openDate = TradingCalendar.dayKey(trade.openTime)
            let isCatalystDay = catalystDates[trade.symbol]?.contains(tradeDate) ?? false
            let openedOnCatalystDay = catalystDates[trade.symbol]?.contains(openDate) ?? false

            if isCatalystDay {
                catalystTrades.append(trade)

                // Held through: opened on a different (non-catalyst) day, closed on catalyst day
                if openDate != tradeDate && !openedOnCatalystDay {
                    heldThroughTrades.append(trade)
                }
            } else {
                normalTrades.append(trade)
            }
        }

        return CatalystAnalysis(
            catalystTrades: catalystTrades,
            normalTrades: normalTrades,
            heldThroughTrades: heldThroughTrades
        )
    }

    // MARK: - Body

    var body: some View {
        if trades.count < 20 {
            EmptyView()
        } else {
            let data = analysis
            let catalystStats = GroupStats.from(data.catalystTrades)
            let normalStats = GroupStats.from(data.normalTrades)

            VStack(alignment: .leading, spacing: 16) {
                header(catalystCount: catalystStats.count)

                if catalystStats.count < 3 {
                    Text("Not enough high-volatility days detected for analysis")
                        .font(.bodyText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    catalystPerformanceSection(catalyst: catalystStats, normal: normalStats)
                    preCatalystSection(data.heldThroughTrades)
                    recommendationSection(catalyst: catalystStats, normal: normalStats)
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
        }
    }

    // MARK: - Header

    private func header(catalystCount: Int) -> some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticAmberDim)
                        .frame(width: 22, height: 22)
                    Image(systemName: "calendar.badge.clock")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticAmber)
                }
                Text("Earnings Impact")
                    .font(.cardTitle)
            }
            Spacer()
            Text("\(catalystCount) catalyst days")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Catalyst Day Performance

    private func catalystPerformanceSection(catalyst: GroupStats, normal: GroupStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATALYST DAY PERFORMANCE")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 12) {
                statCard(
                    title: "CATALYST DAYS",
                    stats: catalyst,
                    color: Color.semanticAmber
                )
                statCard(
                    title: "NORMAL DAYS",
                    stats: normal,
                    color: Color.accent
                )
            }

            // Insight comparison
            let performsBetter = catalyst.avgPnL > normal.avgPnL
            let delta = catalyst.avgPnL - normal.avgPnL
            HStack(spacing: 6) {
                Image(systemName: performsBetter ? "arrow.up.right" : "arrow.down.right")
                    .font(.smallText)
                    .foregroundStyle(performsBetter ? Color.semanticGreen : Color.semanticRed)
                Text("You perform \(performsBetter ? "better" : "worse") on catalyst days (\(String(format: "%+.2f", delta)) avg P&L difference)")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgInset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
        }
    }

    // MARK: - Pre-Catalyst Positioning

    private func preCatalystSection(_ heldThrough: [Trade]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRE-CATALYST POSITIONING")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            if heldThrough.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accent)
                    Text("No positions held through catalyst events detected. You appear to close before high-volatility days.")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(12)
                .background(Color.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                let stats = GroupStats.from(heldThrough)
                let helped = stats.avgPnL > 0

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.arrow.left")
                                .font(.monoSmall)
                                .foregroundStyle(Color.semanticPurple)
                            Text("Held Through Catalyst")
                                .font(.smallText)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trades").font(.monoSmall).foregroundStyle(Color.textTertiary)
                                Text("\(stats.count)")
                                    .font(.monoSubtitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.textPrimary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Win Rate").font(.monoSmall).foregroundStyle(Color.textTertiary)
                                Text(String(format: "%.0f%%", stats.winRate * 100))
                                    .font(.monoSubtitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(stats.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Avg P&L").font(.monoSmall).foregroundStyle(Color.textTertiary)
                                Text(String(format: "%+.2f", stats.avgPnL))
                                    .font(.monoSubtitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.forPnL(stats.avgPnL))
                            }
                        }
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Image(systemName: helped ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.cardTitle)
                            .foregroundStyle(helped ? Color.semanticGreen : Color.semanticRed)
                        Text(helped ? "HELPED" : "HURT")
                            .font(.monoSmall)
                            .foregroundStyle(helped ? Color.semanticGreen : Color.semanticRed)
                    }
                }
                .padding(12)
                .background(Color.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
            }
        }
    }

    // MARK: - Recommendation

    private func recommendationSection(catalyst: GroupStats, normal: GroupStats) -> some View {
        let performsBetter = catalyst.avgPnL > normal.avgPnL
        let wrBetter = catalyst.winRate > normal.winRate
        let significantDifference = abs(catalyst.avgPnL - normal.avgPnL) > abs(normal.avgPnL) * 0.2

        let recommendation: (icon: String, color: Color, label: String, text: String)

        if performsBetter && wrBetter && significantDifference {
            recommendation = (
                "checkmark.seal.fill", Color.semanticGreen, "TRADE",
                "Catalyst days are a strength. Your win rate and average P&L both improve during high-volatility events. Consider increasing size on catalyst days."
            )
        } else if !performsBetter && !wrBetter && significantDifference {
            recommendation = (
                "exclamationmark.shield.fill", Color.semanticRed, "AVOID",
                "High-volatility events hurt your performance. Consider reducing size or sitting out on catalyst days. The data shows \(String(format: "$%.2f", abs(catalyst.avgPnL - normal.avgPnL))) worse per trade."
            )
        } else {
            recommendation = (
                "eye.fill", Color.semanticAmber, "CAUTION",
                "Mixed results on catalyst days. Monitor your performance and consider using smaller position sizes until you have more data."
            )
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("RECOMMENDATION")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 10) {
                Image(systemName: recommendation.icon)
                    .font(.cardTitle)
                    .foregroundStyle(recommendation.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.label)
                        .font(.monoSubtitle)
                        .foregroundStyle(recommendation.color)
                    Text(recommendation.text)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(recommendation.color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(recommendation.color.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Stat Card

    private func statCard(title: String, stats: GroupStats, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win Rate").font(.monoSmall).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.0f%%", stats.winRate * 100))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(stats.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg P&L").font(.monoSmall).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%+.2f", stats.avgPnL))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.forPnL(stats.avgPnL))
                }
            }
            Text("\(stats.count) trades")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(8)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }
}
