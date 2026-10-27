import Foundation

/// Calculates portfolio-level metrics from trade data
struct MetricsCalculator: Sendable {

    struct PortfolioMetrics: Sendable {
        let totalTrades: Int
        let wins: Int
        let losses: Int
        let winRate: Double
        let totalProfit: Double
        let grossProfit: Double
        let grossLoss: Double
        let profitFactor: Double
        let expectancy: Double
        let averageWin: Double
        let averageLoss: Double
        let bestTrade: Double
        let worstTrade: Double
        let maxDrawdown: Double
        let averageRMultiple: Double
        let averageMAE: Double
        let averageMFE: Double
        let maxWinStreak: Int
        let maxLossStreak: Int
        let currentStreak: Int // positive = wins, negative = losses
        let averageDuration: Int // minutes
        let sharpeRatio: Double // Risk-adjusted return
        let calmarRatio: Double // Return / max drawdown
        let totalCommissions: Double // Sum of all commissions
        let totalSwap: Double // Sum of all swap fees
        let totalCosts: Double // commissions + swap
        let netProfitAfterCosts: Double // == totalProfit: trade P&L is already net of costs

        static let empty = PortfolioMetrics(
            totalTrades: 0, wins: 0, losses: 0, winRate: 0,
            totalProfit: 0, grossProfit: 0, grossLoss: 0,
            profitFactor: 0, expectancy: 0, averageWin: 0,
            averageLoss: 0, bestTrade: 0, worstTrade: 0,
            maxDrawdown: 0, averageRMultiple: 0, averageMAE: 0, averageMFE: 0,
            maxWinStreak: 0, maxLossStreak: 0, currentStreak: 0, averageDuration: 0,
            sharpeRatio: 0, calmarRatio: 0,
            totalCommissions: 0, totalSwap: 0, totalCosts: 0, netProfitAfterCosts: 0
        )
    }

    /// Calculate all portfolio metrics from a set of trades
    static func calculate(from trades: [Trade]) -> PortfolioMetrics {
        guard !trades.isEmpty else { return .empty }

        let profits = trades.map { $0.profitDouble }
        let winTrades = trades.filter { $0.isWin }
        let lossTrades = trades.filter { $0.isLoss }

        let grossProfit = winTrades.reduce(0.0) { $0 + $1.profitDouble }
        let grossLoss = abs(lossTrades.reduce(0.0) { $0 + $1.profitDouble })
        let totalProfit = profits.reduce(0, +)

        let winRate = Double(winTrades.count) / Double(trades.count) * 100
        let profitFactor = grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? .infinity : 0
        let avgWin = winTrades.isEmpty ? 0 : grossProfit / Double(winTrades.count)
        let avgLoss = lossTrades.isEmpty ? 0 : grossLoss / Double(lossTrades.count)
        let expectancy = (winRate / 100 * avgWin) - ((1 - winRate / 100) * avgLoss)

        // Max drawdown from equity curve
        var peak = 0.0
        var maxDD = 0.0
        var cumulative = 0.0
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        for trade in sorted {
            cumulative += trade.profitDouble
            peak = max(peak, cumulative)
            maxDD = max(maxDD, peak - cumulative)
        }

        // Streak calculation
        var maxWinStreak = 0, maxLossStreak = 0, currentWinStreak = 0, currentLossStreak = 0
        var currentStreak = 0
        for trade in sorted {
            if trade.isWin {
                currentWinStreak += 1
                currentLossStreak = 0
                maxWinStreak = max(maxWinStreak, currentWinStreak)
            } else if trade.isLoss {
                currentLossStreak += 1
                currentWinStreak = 0
                maxLossStreak = max(maxLossStreak, currentLossStreak)
            }
        }
        // Current streak from last trade
        if let last = sorted.last {
            if last.isWin { currentStreak = currentWinStreak }
            else if last.isLoss { currentStreak = -currentLossStreak }
        }

        // Average trade duration
        let avgDuration = trades.map(\.durationMin).overflowSafeAverage()

        // Sharpe Ratio (using per-trade returns)
        let meanReturn = totalProfit / Double(trades.count)
        let variance = profits.map { pow($0 - meanReturn, 2) }.reduce(0, +) / Double(trades.count)
        let stdDev = sqrt(variance)
        let sharpeRatio = stdDev > 0 ? meanReturn / stdDev : 0

        // Calmar Ratio (total return / max drawdown)
        let calmarRatio = maxDD > 0 ? totalProfit / maxDD : totalProfit > 0 ? 10.0 : 0

        // Commission and swap totals
        let totalCommissions = trades.reduce(0.0) { $0 + $1.commissionDouble }
        let totalSwap = trades.reduce(0.0) { $0 + $1.swapDouble }
        let totalCosts = totalCommissions + totalSwap

        return PortfolioMetrics(
            totalTrades: trades.count,
            wins: winTrades.count,
            losses: lossTrades.count,
            winRate: winRate,
            totalProfit: totalProfit,
            grossProfit: grossProfit,
            grossLoss: grossLoss,
            profitFactor: profitFactor,
            expectancy: expectancy,
            averageWin: avgWin,
            averageLoss: avgLoss,
            bestTrade: profits.max() ?? 0,
            worstTrade: profits.min() ?? 0,
            maxDrawdown: maxDD,
            averageRMultiple: trades.map(\.rMultiple).reduce(0, +) / Double(trades.count),
            averageMAE: trades.map(\.maePoints).reduce(0, +) / Double(trades.count),
            averageMFE: trades.map(\.mfePoints).reduce(0, +) / Double(trades.count),
            maxWinStreak: maxWinStreak,
            maxLossStreak: maxLossStreak,
            currentStreak: currentStreak,
            averageDuration: avgDuration,
            sharpeRatio: sharpeRatio,
            calmarRatio: calmarRatio,
            totalCommissions: totalCommissions,
            totalSwap: totalSwap,
            totalCosts: totalCosts,
            netProfitAfterCosts: totalProfit
        )
    }

    // MARK: - Edge Detection

    struct EdgeBreakdown: Identifiable, Sendable {
        let id = UUID()
        let category: String
        let label: String
        let profit: Double
        let tradeCount: Int
        let winRate: Double
    }

    /// Top profit/loss sources by hour
    static func edgeByHour(from trades: [Trade]) -> [EdgeBreakdown] {
        let grouped = Dictionary(grouping: trades) { $0.hour }
        return grouped.map { hour, hourTrades in
            let profit = hourTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = hourTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(hourTrades.count) * 100
            return EdgeBreakdown(
                category: "Hour", label: "\(hour):00",
                profit: profit, tradeCount: hourTrades.count, winRate: wr
            )
        }.sorted { $0.profit > $1.profit }
    }

    /// Top profit/loss sources by session
    static func edgeBySession(from trades: [Trade]) -> [EdgeBreakdown] {
        let grouped = Dictionary(grouping: trades) { $0.session }
        return grouped.map { session, sessionTrades in
            let profit = sessionTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sessionTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(sessionTrades.count) * 100
            return EdgeBreakdown(
                category: "Session", label: session.displayName,
                profit: profit, tradeCount: sessionTrades.count, winRate: wr
            )
        }.sorted { $0.profit > $1.profit }
    }

    /// Top profit/loss sources by day of week (weekday of the US trading day)
    static func edgeByDay(from trades: [Trade]) -> [EdgeBreakdown] {
        let grouped = TradingCalendar.groupedByWeekday(trades)
        return grouped.map { day, dayTrades in
            let profit = dayTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = dayTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(dayTrades.count) * 100
            return EdgeBreakdown(
                category: "Day", label: day,
                profit: profit, tradeCount: dayTrades.count, winRate: wr
            )
        }.sorted { $0.profit > $1.profit }
    }

    /// Top profit/loss sources by symbol
    static func edgeBySymbol(from trades: [Trade]) -> [EdgeBreakdown] {
        let grouped = Dictionary(grouping: trades) { $0.symbol }
        return grouped.map { symbol, symbolTrades in
            let profit = symbolTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = symbolTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(symbolTrades.count) * 100
            return EdgeBreakdown(
                category: "Symbol", label: symbol,
                profit: profit, tradeCount: symbolTrades.count, winRate: wr
            )
        }.sorted { $0.profit > $1.profit }
    }

    /// Edge by sector
    static func edgeBySector(from trades: [Trade]) -> [EdgeBreakdown] {
        let grouped = Dictionary(grouping: trades) { $0.sector.isEmpty ? "Unknown" : $0.sector }
        return grouped.map { sector, sectorTrades in
            let profit = sectorTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sectorTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(sectorTrades.count) * 100
            return EdgeBreakdown(
                category: "Sector", label: sector,
                profit: profit, tradeCount: sectorTrades.count, winRate: wr
            )
        }.sorted { $0.profit > $1.profit }
    }

    // MARK: - Statistical Confidence

    /// Determine confidence level based on sample size
    static func confidenceLevel(sampleSize: Int) -> ConfidenceLevel {
        if sampleSize < 10 { return .insufficient }
        if sampleSize < 30 { return .low }
        return .significant
    }

    /// Whether sample size meets minimum threshold for actionable patterns
    static func isActionable(sampleSize: Int) -> Bool {
        sampleSize >= 30
    }

    // MARK: - Edge Conditions (Multi-Dimensional)

    /// A single condition (hour, day, session, symbol, etc.) with full metrics
    struct EdgeCondition: Identifiable, Sendable {
        let id: String
        let dimension: String      // "Hour", "Day", "Session", "Symbol"
        let label: String          // "Friday", "10:00", "AAPL"
        let profit: Double
        let tradeCount: Int
        let winRate: Double
        let expectancy: Double
        let profitFactor: Double
        let monthlyImpact: Double  // Dollar amount projected per month

        var dimensionIcon: String {
            switch dimension {
            case "Hour": "clock"
            case "Day": "calendar"
            case "Session": "sun.max"
            case "Symbol": "chart.bar"
            case "Sector": "building.2"
            default: "circle"
            }
        }

        var confidence: ConfidenceLevel {
            MetricsCalculator.confidenceLevel(sampleSize: tradeCount)
        }
    }

    /// Compute edge conditions across all dimensions
    static func allEdgeConditions(from trades: [Trade], tradingDays: Int) -> [EdgeCondition] {
        guard !trades.isEmpty, tradingDays > 0 else { return [] }

        let monthScale = 21.0 / Double(tradingDays) // ~21 trading days/month

        func buildConditions(
            dimension: String,
            grouped: [String: [Trade]]
        ) -> [EdgeCondition] {
            grouped.map { label, group in
                let profit = group.reduce(0.0) { $0 + $1.profitDouble }
                let wins = group.filter(\.isWin).count
                let losses = group.filter(\.isLoss).count
                let winRate = Double(wins) / Double(group.count) * 100
                let grossWin = group.filter(\.isWin).reduce(0.0) { $0 + $1.profitDouble }
                let grossLoss = abs(group.filter(\.isLoss).reduce(0.0) { $0 + $1.profitDouble })
                let avgWin = wins > 0 ? grossWin / Double(wins) : 0
                let avgLoss = losses > 0 ? grossLoss / Double(losses) : 0
                let expectancy = (winRate / 100 * avgWin) - ((1 - winRate / 100) * avgLoss)
                let pf = grossLoss > 0 ? grossWin / grossLoss : grossWin > 0 ? .infinity : 0

                return EdgeCondition(
                    id: "\(dimension)_\(label)",
                    dimension: dimension,
                    label: label,
                    profit: profit,
                    tradeCount: group.count,
                    winRate: winRate,
                    expectancy: expectancy,
                    profitFactor: pf,
                    monthlyImpact: profit * monthScale
                )
            }
        }

        var conditions: [EdgeCondition] = []

        // Hour
        let byHour = Dictionary(grouping: trades) { "\($0.hour):00" }
        conditions.append(contentsOf: buildConditions(dimension: "Hour", grouped: byHour))

        // Day (weekday of the US trading day)
        let byDay = TradingCalendar.groupedByWeekday(trades)
        conditions.append(contentsOf: buildConditions(dimension: "Day", grouped: byDay))

        // Session
        let bySession = Dictionary(grouping: trades) { $0.session.displayName }
        conditions.append(contentsOf: buildConditions(dimension: "Session", grouped: bySession))

        // Symbol
        let bySymbol = Dictionary(grouping: trades) { $0.symbol }
        conditions.append(contentsOf: buildConditions(dimension: "Symbol", grouped: bySymbol))

        // Sector
        let bySector = Dictionary(grouping: trades) { $0.sector.isEmpty ? "Unknown" : $0.sector }
        conditions.append(contentsOf: buildConditions(dimension: "Sector", grouped: bySector))

        return conditions
    }
}
