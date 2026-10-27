import Foundation
import AppKit
import os

/// Exports trade data and analytics as PDF reports
final class PDFExporter: Sendable {
    private static let logger = Logger(subsystem: "com.greenwick", category: "PDFExporter")

    /// Export a journal report with trade list and summary stats
    func exportJournal(trades: [Trade], metrics: MetricsCalculator.PortfolioMetrics, to url: URL) throws {
        let content = buildJournalContent(trades: trades, metrics: metrics)
        let data = try renderPDF(content: content)
        try data.write(to: url)
        Self.logger.info("Journal PDF exported")
    }

    /// Export an edge report with analysis data
    func exportEdgeReport(
        trades: [Trade],
        metrics: MetricsCalculator.PortfolioMetrics,
        edgeBySession: [MetricsCalculator.EdgeBreakdown],
        edgeByHour: [MetricsCalculator.EdgeBreakdown],
        edgeBySymbol: [MetricsCalculator.EdgeBreakdown],
        edgeByDay: [MetricsCalculator.EdgeBreakdown],
        to url: URL
    ) throws {
        let content = buildEdgeContent(
            trades: trades,
            metrics: metrics,
            bySession: edgeBySession,
            byHour: edgeByHour,
            bySymbol: edgeBySymbol,
            byDay: edgeByDay
        )
        let data = try renderPDF(content: content)
        try data.write(to: url)
        Self.logger.info("Edge Report PDF exported")
    }

    /// Export a comprehensive dashboard report with all analytics
    func exportDashboard(
        trades: [Trade],
        metrics: MetricsCalculator.PortfolioMetrics,
        edgeBySession: [MetricsCalculator.EdgeBreakdown],
        edgeByHour: [MetricsCalculator.EdgeBreakdown],
        edgeBySymbol: [MetricsCalculator.EdgeBreakdown],
        edgeByDay: [MetricsCalculator.EdgeBreakdown],
        to url: URL
    ) throws {
        let content = buildDashboardContent(
            trades: trades,
            metrics: metrics,
            bySession: edgeBySession,
            byHour: edgeByHour,
            bySymbol: edgeBySymbol,
            byDay: edgeByDay
        )
        let data = try renderPDF(content: content)
        try data.write(to: url)
        Self.logger.info("Dashboard PDF exported")
    }

    // MARK: - PDF Rendering (Multi-Page)

    private func renderPDF(content: NSAttributedString) throws -> Data {
        let pageSize = CGSize(width: 612, height: 792) // US Letter
        let margins = NSEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
        let contentSize = CGSize(
            width: pageSize.width - margins.left - margins.right,
            height: pageSize.height - margins.top - margins.bottom
        )

        let textStorage = NSTextStorage(attributedString: content)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        // Create enough text containers for all content
        var textContainers: [NSTextContainer] = []
        var hasMoreText = true
        while hasMoreText {
            let container = NSTextContainer(size: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            textContainers.append(container)

            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            // If this container has no glyphs and it's not the first, we're done
            if glyphRange.length == 0 && textContainers.count > 1 {
                textContainers.removeLast()
                hasMoreText = false
            } else {
                // Check if all glyphs are laid out
                let totalGlyphs = layoutManager.numberOfGlyphs
                let lastGlyph = glyphRange.location + glyphRange.length
                hasMoreText = lastGlyph < totalGlyphs
            }
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        let drawOrigin = CGPoint(x: margins.left, y: margins.top)

        for container in textContainers {
            var pageBox = CGRect(origin: .zero, size: pageSize)
            context.beginPage(mediaBox: &pageBox)
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = nsContext

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length > 0 {
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawOrigin)
            }

            context.endPage()
        }

        context.closePDF()
        NSGraphicsContext.current = nil

        return data as Data
    }

    // MARK: - Content Builders

    private func buildJournalContent(trades: [Trade], metrics: MetricsCalculator.PortfolioMetrics) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let dateString = Date().formatted(.dateTime.month().day().year())

        result.append(styled("Greenwick — Trade Journal\n", size: 20, bold: true))
        result.append(styled("Generated \(dateString)\n\n", size: 11, color: .secondaryLabelColor))

        // Summary stats
        result.append(styled("Portfolio Summary\n", size: 14, bold: true))
        result.append(styled("Total Trades: \(metrics.totalTrades)\n", size: 11))
        result.append(styled("Win Rate: \(String(format: "%.1f%%", metrics.winRate))\n", size: 11))
        result.append(styled("Total P&L: \(String(format: "$%.2f", metrics.totalProfit))\n", size: 11))
        result.append(styled("Profit Factor: \(String(format: "%.2f", metrics.profitFactor))\n", size: 11))
        result.append(styled("Expectancy: \(String(format: "$%.2f", metrics.expectancy))/trade\n", size: 11))
        result.append(styled("Max Drawdown: \(String(format: "$%.2f", metrics.maxDrawdown))\n\n", size: 11))

        // Trade list
        result.append(styled("Trade Log (last 50)\n", size: 14, bold: true))
        result.append(styled("Date | Ticker | Dir | P&L | R | Session\n", size: 10, bold: true))
        result.append(styled(String(repeating: "—", count: 60) + "\n", size: 10))

        for trade in trades.prefix(50) {
            // Exchange time (ET), the same dates as the P&L calendar and the journal
            let dateStr = trade.closeTime.formatted(TradingCalendar.formatStyle.month(.twoDigits).day().hour().minute())
            let pnl = String(format: "$%.2f", trade.profitDouble)
            let rMult = String(format: "%.1fR", trade.rMultiple)
            let line = "\(dateStr) | \(trade.symbol) | \(trade.direction.rawValue) | \(pnl) | \(rMult) | \(trade.session.displayName)\n"
            result.append(styled(line, size: 9))
        }

        return result
    }

    private func buildEdgeContent(
        trades: [Trade],
        metrics: MetricsCalculator.PortfolioMetrics,
        bySession: [MetricsCalculator.EdgeBreakdown],
        byHour: [MetricsCalculator.EdgeBreakdown],
        bySymbol: [MetricsCalculator.EdgeBreakdown],
        byDay: [MetricsCalculator.EdgeBreakdown]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let dateString = Date().formatted(.dateTime.month().day().year())

        result.append(styled("Greenwick — Edge Report\n", size: 20, bold: true))
        result.append(styled("Generated \(dateString) | \(metrics.totalTrades) trades analyzed\n\n", size: 11, color: .secondaryLabelColor))

        appendBreakdown(to: result, title: "By Session", data: bySession)
        appendBreakdown(to: result, title: "By Ticker", data: bySymbol)
        appendBreakdown(to: result, title: "By Hour (top 10)", data: Array(byHour.prefix(10)))
        appendBreakdown(to: result, title: "By Day", data: byDay)

        return result
    }

    // MARK: - Dashboard Content Builder

    private func buildDashboardContent(
        trades: [Trade],
        metrics: MetricsCalculator.PortfolioMetrics,
        bySession: [MetricsCalculator.EdgeBreakdown],
        byHour: [MetricsCalculator.EdgeBreakdown],
        bySymbol: [MetricsCalculator.EdgeBreakdown],
        byDay: [MetricsCalculator.EdgeBreakdown]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let dateString = Date().formatted(.dateTime.month().day().year())

        // Title
        result.append(styled("Greenwick — Dashboard Report\n", size: 22, bold: true))
        result.append(styled("Generated \(dateString) | \(metrics.totalTrades) trades analyzed\n", size: 11, color: .secondaryLabelColor))
        result.append(styled(String(repeating: "━", count: 70) + "\n\n", size: 8, color: .tertiaryLabelColor))

        // Key metrics grid (2 columns)
        result.append(styled("KEY METRICS\n\n", size: 13, bold: true))
        let metricsData: [(String, String)] = [
            ("Total P&L", String(format: "$%.2f", metrics.totalProfit)),
            ("Win Rate", String(format: "%.1f%% (%dW / %dL)", metrics.winRate, metrics.wins, metrics.losses)),
            ("Profit Factor", String(format: "%.2f", metrics.profitFactor)),
            ("Expectancy", String(format: "$%.2f / trade", metrics.expectancy)),
            ("Avg Win", String(format: "$%.2f", metrics.averageWin)),
            ("Avg Loss", String(format: "$%.2f", metrics.averageLoss)),
            ("Max Drawdown", String(format: "$%.2f", metrics.maxDrawdown)),
            ("Avg R-Multiple", String(format: "%.2fR", metrics.averageRMultiple)),
            ("Sharpe Ratio", String(format: "%.2f", metrics.sharpeRatio)),
            ("Calmar Ratio", String(format: "%.2f", metrics.calmarRatio)),
            ("Best Trade", String(format: "$%.2f", metrics.bestTrade)),
            ("Worst Trade", String(format: "$%.2f", metrics.worstTrade)),
            ("Max Win Streak", "\(metrics.maxWinStreak)"),
            ("Max Loss Streak", "\(metrics.maxLossStreak)"),
            ("Avg Duration", "\(metrics.averageDuration)m"),
            ("Avg MAE", String(format: "%.2f pts", metrics.averageMAE)),
        ]

        for (label, value) in metricsData {
            let padded = label.padding(toLength: 20, withPad: " ", startingAt: 0)
            result.append(styled("  \(padded)", size: 10))
            result.append(styled("\(value)\n", size: 10, bold: true))
        }
        result.append(styled("\n", size: 8))

        // Trade grade distribution
        appendGradeDistribution(to: result, trades: trades, metrics: metrics)

        // Session performance
        result.append(styled(String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("SESSION PERFORMANCE\n\n", size: 13, bold: true))
        appendBreakdownTable(to: result, data: bySession)
        result.append(styled("\n", size: 8))

        // Ticker performance
        result.append(styled("TICKER PERFORMANCE\n\n", size: 13, bold: true))
        appendBreakdownTable(to: result, data: bySymbol)
        result.append(styled("\n", size: 8))

        // Day of week performance
        result.append(styled("DAY OF WEEK PERFORMANCE\n\n", size: 13, bold: true))
        appendBreakdownTable(to: result, data: byDay)
        result.append(styled("\n", size: 8))

        // Top hours
        result.append(styled("TOP TRADING HOURS (ET)\n\n", size: 13, bold: true))
        appendBreakdownTable(to: result, data: Array(byHour.prefix(10)))
        result.append(styled("\n", size: 8))

        // Monthly P&L summary
        appendMonthlyPnL(to: result, trades: trades)

        // Streak analysis
        appendStreakAnalysis(to: result, metrics: metrics, trades: trades)

        // Risk metrics
        appendRiskMetrics(to: result, trades: trades, metrics: metrics)

        // Footer
        result.append(styled("\n" + String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("Report generated by Greenwick\n", size: 9, color: .tertiaryLabelColor))

        return result
    }

    // MARK: - Dashboard Subsections

    private func appendGradeDistribution(to result: NSMutableAttributedString, trades: [Trade], metrics: MetricsCalculator.PortfolioMetrics) {
        guard trades.count >= 5 else { return }

        result.append(styled(String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("TRADE GRADE DISTRIBUTION\n\n", size: 13, bold: true))

        var counts: [String: Int] = ["A": 0, "B": 0, "C": 0, "D": 0, "F": 0]
        var totalScore = 0

        for trade in trades {
            let grade = TradeGrader.grade(trade, portfolioMetrics: metrics)
            counts[grade.overall.rawValue, default: 0] += 1
            totalScore += grade.total
        }

        let avgScore = trades.isEmpty ? 0 : totalScore / trades.count

        for letter in ["A", "B", "C", "D", "F"] {
            let count = counts[letter] ?? 0
            let pct = trades.isEmpty ? 0.0 : Double(count) / Double(trades.count) * 100
            let bar = String(repeating: "█", count: max(0, min(40, Int(saturating: pct / 2.5))))
            let padded = " \(letter)  ".padding(toLength: 5, withPad: " ", startingAt: 0)
            result.append(styled(padded, size: 10, bold: true))
            result.append(styled("\(bar) \(count) (\(String(format: "%.0f%%", pct)))\n", size: 10))
        }

        result.append(styled("  Average Score: \(avgScore)/100\n\n", size: 10, color: .secondaryLabelColor))
    }

    private func appendBreakdownTable(to result: NSMutableAttributedString, data: [MetricsCalculator.EdgeBreakdown]) {
        // Header
        let header = "  Label".padding(toLength: 16, withPad: " ", startingAt: 0)
            + "P&L".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "Trades".padding(toLength: 10, withPad: " ", startingAt: 0)
            + "Win Rate\n"
        result.append(styled(header, size: 9, bold: true, color: .secondaryLabelColor))
        result.append(styled("  " + String(repeating: "—", count: 45) + "\n", size: 9, color: .tertiaryLabelColor))

        for item in data {
            let label = "  " + item.label.padding(toLength: 14, withPad: " ", startingAt: 0)
            let pnl = String(format: "$%.2f", item.profit).padding(toLength: 14, withPad: " ", startingAt: 0)
            let count = "\(item.tradeCount)t".padding(toLength: 10, withPad: " ", startingAt: 0)
            let wr = String(format: "%.0f%%", item.winRate)
            result.append(styled("\(label)\(pnl)\(count)\(wr)\n", size: 9))
        }
    }

    private func appendMonthlyPnL(to result: NSMutableAttributedString, trades: [Trade]) {
        guard !trades.isEmpty else { return }

        result.append(styled(String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("MONTHLY P&L SUMMARY\n\n", size: 13, bold: true))

        var monthlyPnL: [String: Double] = [:]
        var monthlyCount: [String: Int] = [:]

        for trade in trades {
            let key = TradingCalendar.monthKey(trade.closeTime) // month of the US trading day
            monthlyPnL[key, default: 0] += trade.profitDouble
            monthlyCount[key, default: 0] += 1
        }

        let sorted = monthlyPnL.keys.sorted()
        let header = "  Month".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "P&L".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "Trades\n"
        result.append(styled(header, size: 9, bold: true, color: .secondaryLabelColor))
        result.append(styled("  " + String(repeating: "—", count: 35) + "\n", size: 9, color: .tertiaryLabelColor))

        for key in sorted {
            let pnl = monthlyPnL[key] ?? 0
            let count = monthlyCount[key] ?? 0
            let label = "  " + key.padding(toLength: 12, withPad: " ", startingAt: 0)
            let pnlStr = String(format: "$%.2f", pnl).padding(toLength: 14, withPad: " ", startingAt: 0)
            let marker = pnl >= 0 ? "+" : "−"
            result.append(styled("\(label)\(marker) \(pnlStr)\(count)t\n", size: 9))
        }
        result.append(styled("\n", size: 8))
    }

    private func appendStreakAnalysis(to result: NSMutableAttributedString, metrics: MetricsCalculator.PortfolioMetrics, trades: [Trade]) {
        result.append(styled(String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("STREAK ANALYSIS\n\n", size: 13, bold: true))

        let currentDir = metrics.currentStreak > 0 ? "winning" : metrics.currentStreak < 0 ? "losing" : "neutral"
        result.append(styled("  Current Streak:    \(abs(metrics.currentStreak)) \(currentDir)\n", size: 10))
        result.append(styled("  Best Win Streak:   \(metrics.maxWinStreak)\n", size: 10))
        result.append(styled("  Worst Loss Streak: \(metrics.maxLossStreak)\n\n", size: 10))
    }

    private func appendRiskMetrics(to result: NSMutableAttributedString, trades: [Trade], metrics: MetricsCalculator.PortfolioMetrics) {
        guard trades.count >= 10 else { return }

        result.append(styled(String(repeating: "━", count: 70) + "\n", size: 8, color: .tertiaryLabelColor))
        result.append(styled("RISK ASSESSMENT\n\n", size: 13, bold: true))

        // Kelly criterion
        let winRate = Double(metrics.wins) / Double(metrics.totalTrades)
        let rewardRisk = metrics.averageLoss > 0 ? metrics.averageWin / metrics.averageLoss : 0
        let kellyFraction = rewardRisk > 0 ? winRate - (1 - winRate) / rewardRisk : 0

        result.append(styled("  Win Rate:          \(String(format: "%.1f%%", winRate * 100))\n", size: 10))
        result.append(styled("  Reward:Risk Ratio: \(String(format: "%.2f", rewardRisk))\n", size: 10))
        result.append(styled("  Kelly Fraction:    \(String(format: "%.1f%%", kellyFraction * 100))\n", size: 10))
        result.append(styled("  Sharpe Ratio:      \(String(format: "%.2f", metrics.sharpeRatio))\n", size: 10))
        result.append(styled("  Calmar Ratio:      \(String(format: "%.2f", metrics.calmarRatio))\n\n", size: 10))

        // Position sizing consistency
        let shareSizes = trades.map(\.shares)
        let avgShares = shareSizes.reduce(0, +) / Double(shareSizes.count)
        let maxShares = shareSizes.max() ?? 0
        let shareCV = coefficientOfVariation(shareSizes)

        result.append(styled("  Avg Share Size:    \(String(format: "%.0f", avgShares))\n", size: 10))
        result.append(styled("  Max Share Size:    \(String(format: "%.0f", maxShares))\n", size: 10))
        result.append(styled("  Sizing Consistency: \(shareCV < 0.2 ? "Excellent" : shareCV < 0.5 ? "Good" : "Needs work") (CV: \(String(format: "%.2f", shareCV)))\n\n", size: 10))
    }

    private func coefficientOfVariation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean != 0 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return sqrt(variance) / abs(mean)
    }

    // MARK: - Helpers

    private func appendBreakdown(to result: NSMutableAttributedString, title: String, data: [MetricsCalculator.EdgeBreakdown]) {
        result.append(styled("\(title)\n", size: 14, bold: true))
        for item in data {
            let pnl = String(format: "$%.2f", item.profit)
            let wr = String(format: "%.0f%%", item.winRate)
            result.append(styled("  \(item.label): \(pnl) (\(item.tradeCount)t, \(wr) WR)\n", size: 10))
        }
        result.append(styled("\n", size: 10))
    }

    private func styled(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = .labelColor) -> NSAttributedString {
        let font: NSFont = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    enum ExportError: LocalizedError {
        case pdfCreationFailed

        var errorDescription: String? {
            switch self {
            case .pdfCreationFailed: "Failed to create PDF document"
            }
        }
    }
}
