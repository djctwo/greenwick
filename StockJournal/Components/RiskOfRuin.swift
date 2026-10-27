import SwiftUI
import Charts

/// Calculates and displays risk of ruin based on win rate, risk per trade, and reward:risk ratio
struct RiskOfRuin: View {
    let trades: [Trade]

    private var winRate: Double {
        guard !trades.isEmpty else { return 0 }
        return Double(trades.filter(\.isWin).count) / Double(trades.count)
    }

    private var avgWin: Double {
        let wins = trades.filter(\.isWin)
        guard !wins.isEmpty else { return 0 }
        return wins.map(\.profitDouble).reduce(0, +) / Double(wins.count)
    }

    private var avgLoss: Double {
        let losses = trades.filter(\.isLoss)
        guard !losses.isEmpty else { return 0 }
        return abs(losses.map(\.profitDouble).reduce(0, +)) / Double(losses.count)
    }

    private var rewardRiskRatio: Double {
        guard avgLoss > 0 else { return 0 }
        return avgWin / avgLoss
    }

    /// Risk of ruin using the simplified formula:
    /// RoR = ((1 - edge) / (1 + edge))^units
    /// where edge = (winRate * rewardRisk - (1 - winRate))
    private var riskOfRuin: Double {
        let w = winRate
        let rr = rewardRiskRatio
        guard w > 0, rr > 0 else { return 1.0 }

        let edge = w * rr - (1 - w)
        guard edge > 0 else { return 1.0 } // No edge = 100% ruin eventually

        // Kelly-based approximation
        let q = 1 - w
        guard w != q else { return 1.0 }

        // Using the standard formula: ((q/p)^n) where p = adjusted win prob
        // Simplified: RoR ≈ ((1 - edge) / (1 + edge))^units
        // Use 20 risk units as standard (5% risk per trade on account)
        let base = (1 - edge) / (1 + edge)
        guard base >= 0, base < 1 else { return base >= 1 ? 1.0 : 0.0 }
        let units = 20.0 // Represents trading with 5% risk per trade
        return pow(base, units)
    }

    private var kellyFraction: Double {
        let w = winRate
        let rr = rewardRiskRatio
        guard rr > 0 else { return 0 }
        // Kelly Criterion: f = W - (1-W)/R
        let kelly = w - (1 - w) / rr
        return max(0, kelly)
    }

    private var rorLevel: RoRLevel {
        if riskOfRuin < 0.01 { return .veryLow }
        if riskOfRuin < 0.05 { return .low }
        if riskOfRuin < 0.20 { return .moderate }
        if riskOfRuin < 0.50 { return .high }
        return .veryHigh
    }

    private enum RoRLevel {
        case veryLow, low, moderate, high, veryHigh

        var label: String {
            switch self {
            case .veryLow: "Very Low"
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            case .veryHigh: "Very High"
            }
        }

        var color: Color {
            switch self {
            case .veryLow: Color.semanticGreen
            case .low: Color.semanticGreen.opacity(0.7)
            case .moderate: .orange
            case .high: Color.semanticRed.opacity(0.8)
            case .veryHigh: Color.semanticRed
            }
        }

        var icon: String {
            switch self {
            case .veryLow: "shield.checkmark.fill"
            case .low: "shield.fill"
            case .moderate: "exclamationmark.shield.fill"
            case .high: "exclamationmark.triangle.fill"
            case .veryHigh: "xmark.shield.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Risk of Ruin", systemImage: "shield.lefthalf.filled")
                .font(.cardTitle)

            if trades.count < 10 {
                Text("Need at least 10 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Risk gauge
                HStack(spacing: 16) {
                    // RoR indicator
                    VStack(spacing: 4) {
                        Image(systemName: rorLevel.icon)
                            .font(.kpiValueSecondary)
                            .foregroundStyle(rorLevel.color)
                        Text(String(format: "%.1f%%", riskOfRuin * 100))
                            .font(.cardTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(rorLevel.color)
                        Text(rorLevel.label)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(width: 90)

                    // Stats
                    VStack(alignment: .leading, spacing: 6) {
                        statRow("Win Rate", String(format: "%.1f%%", winRate * 100))
                        statRow("Reward:Risk", String(format: "%.2f", rewardRiskRatio))
                        statRow("Kelly %", String(format: "%.1f%%", kellyFraction * 100))
                        statRow("Half-Kelly", String(format: "%.1f%%", kellyFraction * 50))
                    }

                    Spacer()
                }

                // Risk bar visualization
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(rorLevel.color)
                            .frame(width: max(4, geometry.size.width * min(riskOfRuin, 1.0)))
                    }
                }
                .frame(height: 8)

                // Insight
                HStack(spacing: 4) {
                    Image(systemName: insightIcon)
                        .font(.smallText)
                        .foregroundStyle(rorLevel.color)
                    Text(insightText)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 75, alignment: .leading)
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
        }
    }

    private var insightIcon: String {
        rorLevel == .veryLow || rorLevel == .low ? "checkmark.circle" : "exclamationmark.circle"
    }

    private var insightText: String {
        switch rorLevel {
        case .veryLow:
            return "Excellent risk profile — your edge protects capital well"
        case .low:
            return "Good risk management — consider maintaining current position sizing"
        case .moderate:
            return "Moderate risk — reduce position size or improve win rate to lower ruin probability"
        case .high:
            return "High risk of ruin — significantly reduce risk per trade (use half-Kelly sizing)"
        case .veryHigh:
            return "Critical — stop trading until edge improves. Current stats lead to account blowup"
        }
    }
}
