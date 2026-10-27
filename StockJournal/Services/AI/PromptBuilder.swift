import Foundation

/// Builds prompts for Claude API trade analysis
struct PromptBuilder: Sendable {

    // MARK: - System Prompt

    static let systemPrompt = """
    You are an expert stock trade analyst embedded in Greenwick, a trading journal app. \
    You analyze trade data and provide specific, actionable recommendations ranked by dollar impact.

    Rules:
    - Every recommendation MUST include a dollar impact estimate
    - Use plain English, no jargon without explanation
    - Rank recommendations from highest to lowest dollar impact
    - Be specific: name exact hours, sessions, days, tickers
    - Minimum 30 trades before making recommendations (warn if fewer)
    - Focus on what the trader should CHANGE, not just what happened
    - Format each recommendation as: [Action] — [Reason] — [Dollar Impact]

    You understand stock trading concepts: market sessions (pre-market/regular/after-hours), \
    kill zones, MAE/MFE, R-multiples, volume analysis, sector exposure, and position sizing.
    """

    // MARK: - Analysis Prompts

    /// Build prompt for edge analysis with trade data
    static func edgeAnalysis(from trades: [Trade], metrics: MetricsCalculator.PortfolioMetrics) -> String {
        var prompt = "Analyze my trading data and give me 3-5 specific recommendations to improve profitability.\n\n"

        // Summary stats
        prompt += "## Portfolio Summary\n"
        prompt += "- Total trades: \(metrics.totalTrades)\n"
        prompt += "- Win rate: \(metrics.winRate.asPercent)\n"
        prompt += "- Profit factor: \(metrics.profitFactor.asProfitFactor)\n"
        prompt += "- Total P&L: \(metrics.totalProfit.asCurrency)\n"
        prompt += "- Expectancy: \(metrics.expectancy.asCurrency)/trade\n"
        prompt += "- Avg win: \(metrics.averageWin.asCurrency), Avg loss: \((-metrics.averageLoss).asCurrency)\n"
        prompt += "- Max drawdown: \(metrics.maxDrawdown.asCurrency)\n"
        prompt += "- Avg R-multiple: \(metrics.averageRMultiple.asRMultiple)\n"
        prompt += "- Avg MAE: \(metrics.averageMAE.asPoints), Avg MFE: \(metrics.averageMFE.asPoints)\n\n"

        // Session breakdown
        prompt += "## P&L by Session\n"
        let bySession = MetricsCalculator.edgeBySession(from: trades)
        for s in bySession {
            prompt += "- \(s.label): \(s.profit.asCurrency) (\(s.tradeCount) trades, \(s.winRate.asPercent) WR)\n"
        }
        prompt += "\n"

        // Hour breakdown (top 5 best and worst)
        prompt += "## P&L by Hour (Top 5 Best / Worst)\n"
        let byHour = MetricsCalculator.edgeByHour(from: trades)
        let bestHours = Array(byHour.filter { $0.profit > 0 }.prefix(5))
        let worstHours = Array(byHour.filter { $0.profit < 0 }.suffix(5).reversed())
        prompt += "Best: "
        prompt += bestHours.map { "\($0.label) \($0.profit.asCurrency)" }.joined(separator: ", ")
        prompt += "\nWorst: "
        prompt += worstHours.map { "\($0.label) \($0.profit.asCurrency)" }.joined(separator: ", ")
        prompt += "\n\n"

        // Ticker breakdown
        prompt += "## P&L by Ticker\n"
        let bySymbol = MetricsCalculator.edgeBySymbol(from: trades)
        for p in bySymbol {
            prompt += "- \(p.label): \(p.profit.asCurrency) (\(p.tradeCount) trades, \(p.winRate.asPercent) WR)\n"
        }
        prompt += "\n"

        // Day breakdown
        prompt += "## P&L by Day\n"
        let byDay = MetricsCalculator.edgeByDay(from: trades)
        for d in byDay {
            prompt += "- \(d.label): \(d.profit.asCurrency) (\(d.tradeCount) trades, \(d.winRate.asPercent) WR)\n"
        }
        prompt += "\n"

        // R-multiple distribution
        let rMultiples = trades.map(\.rMultiple)
        let bigWins = rMultiples.filter { $0 >= 2.0 }.count
        let smallWins = rMultiples.filter { $0 > 0 && $0 < 1.0 }.count
        let bigLosses = rMultiples.filter { $0 <= -1.0 }.count
        prompt += "## R-Multiple Distribution\n"
        prompt += "- 2R+ wins: \(bigWins), <1R wins: \(smallWins), -1R+ losses: \(bigLosses)\n"
        prompt += "- This tells you about trade management quality\n\n"

        // Trade duration patterns
        let avgDurWins = trades.filter(\.isWin).map(\.durationMin).overflowSafeAverage()
        let avgDurLosses = trades.filter(\.isLoss).map(\.durationMin).overflowSafeAverage()
        prompt += "## Duration Patterns\n"
        prompt += "- Avg winner duration: \(avgDurWins) min\n"
        prompt += "- Avg loser duration: \(avgDurLosses) min\n"
        prompt += "- If losers last longer, the trader may be holding losers hoping for recovery\n\n"

        // Share size consistency
        let shareSizes = trades.map(\.shares)
        let avgShares = shareSizes.reduce(0, +) / Double(shareSizes.count)
        let maxShares = shareSizes.max() ?? 0
        let minShares = shareSizes.min() ?? 0
        if maxShares > avgShares * 2 {
            prompt += "## Position Sizing Warning\n"
            prompt += "- Avg shares: \(String(format: "%.0f", avgShares)), Max: \(String(format: "%.0f", maxShares)), Min: \(String(format: "%.0f", minShares))\n"
            prompt += "- Max share size is 2x+ the average — possible revenge trading or over-sizing\n\n"
        }

        prompt += "Give me 3-5 specific, ranked recommendations with dollar impact estimates."

        return prompt
    }

    /// Build prompt for daily summary
    static func dailySummary(trades: [Trade]) -> String {
        guard !trades.isEmpty else {
            return "No trades today. Provide a brief encouraging note about patience and waiting for setups."
        }

        var prompt = "Summarize today's trading in 3-4 sentences:\n\n"
        let profit = trades.reduce(0.0) { $0 + $1.profitDouble }
        let wins = trades.filter(\.isWin).count

        prompt += "- \(trades.count) trades, \(wins) wins, \(trades.count - wins) losses\n"
        prompt += "- Total P&L: \(profit.asCurrency)\n"
        prompt += "- Tickers: \(Set(trades.map(\.symbol)).sorted().joined(separator: ", "))\n"
        prompt += "- Sessions: \(Set(trades.map { $0.session.displayName }).sorted().joined(separator: ", "))\n"

        return prompt
    }
}
