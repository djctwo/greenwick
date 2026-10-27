import SwiftUI

/// Auto-grades each trade based on execution quality metrics
struct TradeGrader {

    struct TradeGrade: Sendable {
        let overall: Grade
        let rScore: Int         // R-multiple quality (0-25)
        let executionScore: Int // MAE/MFE efficiency (0-25)
        let timingScore: Int    // Session/hour edge alignment (0-25)
        let managementScore: Int // Duration, bias alignment (0-25)
        let total: Int          // Sum of all (0-100)

        enum Grade: String, Sendable {
            case a = "A"
            case b = "B"
            case c = "C"
            case d = "D"
            case f = "F"

            var color: Color {
                switch self {
                case .a: Color.semanticGreen
                case .b: Color.semanticBlue
                case .c: Color.semanticAmber
                case .d: Color.semanticRed.opacity(0.7)
                case .f: Color.semanticRed
                }
            }
        }
    }

    /// Grade a single trade against portfolio context
    static func grade(_ trade: Trade, portfolioMetrics: MetricsCalculator.PortfolioMetrics) -> TradeGrade {
        let rScore = gradeRMultiple(trade)
        let executionScore = gradeExecution(trade)
        let timingScore = gradeTiming(trade)
        let managementScore = gradeManagement(trade, metrics: portfolioMetrics)
        let total = rScore + executionScore + timingScore + managementScore

        let overall: TradeGrade.Grade
        if total >= 80 { overall = .a }
        else if total >= 65 { overall = .b }
        else if total >= 50 { overall = .c }
        else if total >= 35 { overall = .d }
        else { overall = .f }

        return TradeGrade(
            overall: overall,
            rScore: rScore,
            executionScore: executionScore,
            timingScore: timingScore,
            managementScore: managementScore,
            total: total
        )
    }

    /// R-Multiple scoring (0-25 points)
    /// >2R = 25, >1R = 20, >0.5R = 15, >0R = 10, <0R = 0-5
    private static func gradeRMultiple(_ trade: Trade) -> Int {
        if trade.rMultiple >= 3.0 { return 25 }
        if trade.rMultiple >= 2.0 { return 22 }
        if trade.rMultiple >= 1.5 { return 20 }
        if trade.rMultiple >= 1.0 { return 17 }
        if trade.rMultiple >= 0.5 { return 13 }
        if trade.rMultiple >= 0 { return 8 }
        if trade.rMultiple >= -0.5 { return 5 }
        if trade.rMultiple >= -1.0 { return 3 }
        return 0
    }

    /// Execution quality — MFE:MAE ratio (0-25 points)
    /// How well did entry and exit capture the available move?
    private static func gradeExecution(_ trade: Trade) -> Int {
        let mfeMaeRatio = trade.maePoints > 0 ? trade.mfePoints / trade.maePoints : trade.mfePoints > 0 ? 10 : 0

        var score = 0
        // MFE:MAE ratio (up to 15 points)
        if mfeMaeRatio >= 3 { score += 15 }
        else if mfeMaeRatio >= 2 { score += 12 }
        else if mfeMaeRatio >= 1.5 { score += 10 }
        else if mfeMaeRatio >= 1 { score += 7 }
        else { score += 3 }

        // Low slippage bonus (up to 5 points)
        if trade.slippagePoints <= 0.5 { score += 5 }
        else if trade.slippagePoints <= 1.0 { score += 3 }
        else if trade.slippagePoints <= 2.0 { score += 1 }

        return min(25, score)
    }

    /// Timing quality — did the trade happen during a good session/hour? (0-25 points)
    private static func gradeTiming(_ trade: Trade) -> Int {
        var score = 0

        // Session scoring (up to 10 points)
        switch trade.session {
        case .regular:
            score += 10 // Prime session
        case .preMarket:
            score += 7
        case .afterHours:
            score += 5
        case .extended:
            score += 2
        }

        // Hour scoring — prime hours get more points (up to 10 points)
        // Market open: 9-10 ET, Power hour: 15-16 ET
        if (9...10).contains(trade.hour) || (15...16).contains(trade.hour) {
            score += 10
        } else if (10...12).contains(trade.hour) || (13...15).contains(trade.hour) {
            score += 7
        } else if (4...9).contains(trade.hour) {
            score += 4
        } else {
            score += 1
        }

        return min(25, score)
    }

    /// Trade management quality (0-25 points)
    private static func gradeManagement(_ trade: Trade, metrics: MetricsCalculator.PortfolioMetrics) -> Int {
        var score = 0

        // Hit breakeven → good management (5 points)
        if trade.hitBreakeven && trade.isWin { score += 5 }

        // Duration vs average — extreme durations are worse (up to 10 points)
        let avgDur = max(metrics.averageDuration, 1)
        let durRatio = Double(trade.durationMin) / Double(avgDur)
        if durRatio >= 0.5 && durRatio <= 2.0 {
            score += 10 // Within normal range
        } else if durRatio >= 0.25 && durRatio <= 3.0 {
            score += 6
        } else {
            score += 2 // Extreme outlier duration
        }

        // Exit timing — for losses, quick cut is better (up to 10 points)
        if trade.isWin {
            // For wins, check exit efficiency
            if let eff = trade.exitEfficiency, eff > 60 {
                score += 10
            } else if let eff = trade.exitEfficiency, eff > 30 {
                score += 6
            } else {
                score += 2
            }
        } else {
            // For losses, quick cut is better
            if trade.durationMin <= max(avgDur / 2, 5) {
                score += 8 // Quick cut
            } else {
                score += 4
            }
        }

        return min(25, score)
    }
}

// MARK: - Grade Badge View

struct GradeBadge: View {
    let grade: TradeGrader.TradeGrade

    private var gradeDescription: String {
        switch grade.overall {
        case .a: "Excellent"
        case .b: "Good"
        case .c: "Average"
        case .d: "Below average"
        case .f: "Poor"
        }
    }

    var body: some View {
        Text(grade.overall.rawValue)
            .font(.sidebarItem)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 26, height: 26)
            .background(grade.overall.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Grade: \(grade.overall.rawValue), \(gradeDescription)")
    }
}
