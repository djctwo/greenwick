import SwiftUI

/// Analyzes overnight gap behavior and its impact on trading
struct GapAnalysis: View {
    let trades: [Trade]

    // MARK: - Types

    private enum GapType: String {
        case up = "Gap Up"
        case down = "Gap Down"
    }

    private struct GapTrade {
        let trade: Trade
        let gapType: GapType
        let gapPercent: Double
        let previousClose: Double
        let gapFilled: Bool
    }

    private struct GapStats {
        let type: GapType
        let count: Int
        let avgPnL: Double
        let winRate: Double
        let totalPnL: Double
        let fillRate: Double
    }

    // MARK: - Computed Data

    private var gapTrades: [GapTrade] {
        // Group trades by symbol
        let bySymbol = Dictionary(grouping: trades) { $0.symbol }
        var results: [GapTrade] = []

        for (_, symbolTrades) in bySymbol {
            // Sort by open time
            let sorted = symbolTrades.sorted { $0.openTime < $1.openTime }

            // Group by trading day
            // Zero-padded keys ("2026-03-09") so they sort in date order
            let byDay = Dictionary(grouping: sorted) { TradingCalendar.dayKey($0.openTime) }

            let dayKeys = byDay.keys.sorted()
            guard dayKeys.count >= 2 else { continue }

            for i in 1..<dayKeys.count {
                let prevDayKey = dayKeys[i - 1]
                let currDayKey = dayKeys[i]

                guard let prevDayTrades = byDay[prevDayKey],
                      let currDayTrades = byDay[currDayKey] else { continue }

                // Previous day's last close
                guard let lastTradeYesterday = prevDayTrades.max(by: { $0.closeTime < $1.closeTime }) else { continue }
                let prevClose = NSDecimalNumber(decimal: lastTradeYesterday.closePrice).doubleValue

                // Current day's first trade
                guard let firstTradeToday = currDayTrades.min(by: { $0.openTime < $1.openTime }) else { continue }
                let todayOpen = NSDecimalNumber(decimal: firstTradeToday.openPrice).doubleValue

                guard prevClose > 0 else { continue }

                let gapPercent = (todayOpen - prevClose) / prevClose * 100

                // Only count significant gaps (>0.5%)
                guard abs(gapPercent) > 0.5 else { continue }

                let gapType: GapType = gapPercent > 0 ? .up : .down

                // Check if gap filled: did any trade in current day cross previous close?
                let gapFilled = currDayTrades.contains { trade in
                    let closeVal = NSDecimalNumber(decimal: trade.closePrice).doubleValue
                    let openVal = NSDecimalNumber(decimal: trade.openPrice).doubleValue
                    let tradeHigh = max(openVal, closeVal)
                    let tradeLow = min(openVal, closeVal)

                    if gapType == .up {
                        return tradeLow <= prevClose
                    } else {
                        return tradeHigh >= prevClose
                    }
                }

                // All trades from current day that opened in gap territory
                for trade in currDayTrades {
                    results.append(GapTrade(
                        trade: trade,
                        gapType: gapType,
                        gapPercent: gapPercent,
                        previousClose: prevClose,
                        gapFilled: gapFilled
                    ))
                }
            }
        }

        return results
    }

    private func stats(for type: GapType) -> GapStats {
        let matching = gapTrades.filter { $0.gapType == type }
        let count = matching.count
        let totalPnL = matching.reduce(0.0) { $0 + $1.trade.profitDouble }
        let avgPnL = count > 0 ? totalPnL / Double(count) : 0
        let wins = matching.filter { $0.trade.isWin }.count
        let winRate = count > 0 ? Double(wins) / Double(count) * 100 : 0
        let filled = matching.filter(\.gapFilled).count
        let fillRate = count > 0 ? Double(filled) / Double(count) * 100 : 0

        return GapStats(
            type: type,
            count: count,
            avgPnL: avgPnL,
            winRate: winRate,
            totalPnL: totalPnL,
            fillRate: fillRate
        )
    }

    private var hasEnoughData: Bool {
        gapTrades.count >= 2
    }

    private var overallFillRate: Double {
        guard !gapTrades.isEmpty else { return 0 }
        // Deduplicate by day+symbol to get unique gap events
        var seenGaps: Set<String> = []
        var filledCount = 0
        var totalCount = 0

        for gap in gapTrades {
            let key = "\(gap.trade.symbol)-\(TradingCalendar.dayKey(gap.trade.openTime))"
            if seenGaps.insert(key).inserted {
                totalCount += 1
                if gap.gapFilled { filledCount += 1 }
            }
        }

        return totalCount > 0 ? Double(filledCount) / Double(totalCount) * 100 : 0
    }

    private var bestStrategy: String {
        let upStats = stats(for: .up)
        let downStats = stats(for: .down)

        if upStats.count < 3 && downStats.count < 3 {
            return "Need more gap trades to determine best strategy"
        }

        // Compare gap-and-go (trading with the gap) vs gap-and-fade (trading against)
        // Approximate: buys on gap ups = gap-and-go, sells on gap ups = gap-and-fade
        let gapAndGoBuys = gapTrades.filter { $0.gapType == .up && $0.trade.direction == .buy }
        let gapAndFadeSells = gapTrades.filter { $0.gapType == .up && $0.trade.direction == .sell }
        let gapAndGoPnL = gapAndGoBuys.isEmpty ? 0 : gapAndGoBuys.reduce(0.0) { $0 + $1.trade.profitDouble } / Double(gapAndGoBuys.count)
        let gapAndFadePnL = gapAndFadeSells.isEmpty ? 0 : gapAndFadeSells.reduce(0.0) { $0 + $1.trade.profitDouble } / Double(gapAndFadeSells.count)

        if gapAndGoBuys.isEmpty && gapAndFadeSells.isEmpty {
            return "Need both long and short gap trades to compare strategies"
        }

        if gapAndGoPnL > gapAndFadePnL {
            return "Gap-and-go works better for you (avg \(gapAndGoPnL.asCurrency) vs \(gapAndFadePnL.asCurrency) fade)"
        } else if gapAndFadePnL > gapAndGoPnL {
            return "Gap-and-fade works better for you (avg \(gapAndFadePnL.asCurrency) vs \(gapAndGoPnL.asCurrency) go)"
        } else {
            return "Gap-and-go and gap-and-fade perform similarly"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gap Analysis", systemImage: "arrow.up.arrow.down")
                .font(.cardTitle)

            if !hasEnoughData {
                Text("Need more trades to detect gap patterns")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Gap Up vs Gap Down stats
                HStack(spacing: 16) {
                    gapStatCard(stats(for: .up))
                    gapStatCard(stats(for: .down))
                }

                // Gap Fill Rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gap Fill Rate")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    HStack(spacing: 8) {
                        // Fill rate bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.bgInset)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.semanticBlue.opacity(0.7))
                                    .frame(width: max(geo.size.width * overallFillRate / 100, 0), height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text(overallFillRate.asPercent)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.semanticBlue)
                    }

                    Text("\(String(format: "%.0f", overallFillRate))% of gaps eventually fill during the session")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                // Best strategy insight
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Color.semanticAmber)
                        .font(.smallText)
                    Text(bestStrategy)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private func gapStatCard(_ stat: GapStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: stat.type == .up ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(stat.type == .up ? Color.semanticGreen : Color.semanticRed)
                    .font(.smallText)
                Text(stat.type.rawValue)
                    .font(.smallText)
                    .foregroundStyle(Color.textPrimary)
            }

            if stat.count == 0 {
                Text("No data")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)
            } else {
                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text("\(stat.count)")
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                        Text("Trades")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                    VStack(spacing: 1) {
                        Text(stat.winRate.asPercent)
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                        Text("Win")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                    VStack(spacing: 1) {
                        Text(stat.avgPnL.asCurrency)
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.forPnL(stat.avgPnL))
                        Text("Avg")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
