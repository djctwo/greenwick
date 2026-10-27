import SwiftUI

/// Dynamic "Daily Brief" showing the 3 most important signals for the trader right now.
/// Replaces the static single-insight QuickInsight with actionable, prioritized cards.
struct DailyBrief: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var signals: [Signal] {
        generateSignals().prefix(3).map { $0 }
    }

    var body: some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.accent)
                    Text("Daily Brief")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                        Text("Updated \(Date().formatted(.dateTime.hour().minute()))")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary.opacity(0.6))
                    }
                }

                // Signal cards — staggered entrance
                ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                    signalCard(signal, isFirst: index == 0)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 8))
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.1),
                            value: appeared
                        )
                }
            }
            .padding(16)
            .heroCard()
            .accentTopBar()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                appeared = true
            }
        }
    }

    // MARK: - Signal Card

    private func signalCard(_ signal: Signal, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            // Severity indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(signal.color)
                .frame(width: 3, height: isFirst ? 48 : 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: signal.icon)
                        .font(.smallText)
                        .foregroundStyle(signal.color)
                    Text(signal.title)
                        .font(isFirst ? .cardTitle : .bodyText)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Text(signal.detail)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if let value = signal.value {
                Text(value)
                    .font(.kpiValueSecondary)
                    .tracking(-0.5)
                    .foregroundStyle(signal.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isFirst ? 12 : 8)
        .background(signal.color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.title). \(signal.detail)\(signal.value.map { " Value: \($0)" } ?? "")")
    }

    // MARK: - Signal Model

    private struct Signal: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let value: String?
        let color: Color
        let priority: Int // lower = more important
    }

    // MARK: - Signal Generation

    private func generateSignals() -> [Signal] {
        guard trades.count >= 5 else { return [] }

        var signals: [Signal] = []

        // Recent performance trend (last 10 vs previous 10)
        let sorted = trades.sorted { $0.closeTime > $1.closeTime }
        if sorted.count >= 20 {
            let recent10 = Array(sorted.prefix(10))
            let previous10 = Array(sorted[10..<20])
            let recentPnL = Double(truncating: recent10.reduce(into: Decimal.zero) { $0 += $1.netProfit } as NSDecimalNumber)
            let previousPnL = Double(truncating: previous10.reduce(into: Decimal.zero) { $0 += $1.netProfit } as NSDecimalNumber)
            let recentWR = Double(recent10.filter { $0.netProfit > 0 }.count) / 10.0 * 100

            if recentPnL > previousPnL * 1.5 && recentPnL > 0 {
                signals.append(Signal(
                    icon: "arrow.up.right",
                    title: "Hot streak — last 10 trades trending up",
                    detail: "Recent P&L \(recentPnL.asCurrency) vs previous \(previousPnL.asCurrency). Win rate \(recentWR.asPercent).",
                    value: recentPnL.asCurrency,
                    color: .semanticGreen,
                    priority: 1
                ))
            } else if recentPnL < 0 && previousPnL > 0 {
                signals.append(Signal(
                    icon: "arrow.down.right",
                    title: "Performance dip — last 10 trades negative",
                    detail: "Recent P&L \(recentPnL.asCurrency) vs previous \(previousPnL.asCurrency). Review recent entries.",
                    value: recentPnL.asCurrency,
                    color: .semanticRed,
                    priority: 0
                ))
            }
        }

        // Strongest session right now
        let currentSession = Date().marketSession
        let sessionTrades = trades.filter { $0.session == currentSession }
        if sessionTrades.count >= 3 {
            let sessionPnL = Double(truncating: sessionTrades.reduce(into: Decimal.zero) { $0 += $1.netProfit } as NSDecimalNumber)
            let sessionWR = Double(sessionTrades.filter { $0.netProfit > 0 }.count) / Double(sessionTrades.count) * 100
            let signal = sessionPnL > 0 ? "edge" : "caution"
            signals.append(Signal(
                icon: sessionPnL > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                title: "\(currentSession.displayName) session: \(signal) based on \(sessionTrades.count) trades",
                detail: "Your \(currentSession.displayName) history: \(sessionWR.asPercent) WR, \(sessionPnL.asCurrency) total.",
                value: sessionWR.asPercent,
                color: sessionPnL > 0 ? .semanticGreen : .semanticAmber,
                priority: 2
            ))
        }

        // Best symbol by P&L
        let bySymbol = MetricsCalculator.edgeBySymbol(from: trades)
        if let best = bySymbol.max(by: { $0.profit < $1.profit }), best.profit > 0 {
            signals.append(Signal(
                icon: "star.fill",
                title: "\(best.label) is your top performer",
                detail: "\(best.tradeCount) trades, \(best.winRate.asPercent) win rate.",
                value: best.profit.asCurrency,
                color: .semanticBlue,
                priority: 3
            ))
        }

        // Worst symbol bleeding money
        if let worst = bySymbol.min(by: { $0.profit < $1.profit }), worst.profit < 0 {
            signals.append(Signal(
                icon: "xmark.circle.fill",
                title: "\(worst.label) is costing you \(worst.profit.asCurrency)",
                detail: "\(worst.tradeCount) trades at \(worst.winRate.asPercent) WR. Consider sitting out or reducing size.",
                value: nil,
                color: .semanticRed,
                priority: 1
            ))
        }

        // Drawdown warning
        if metrics.maxDrawdown > metrics.totalProfit && metrics.totalProfit > 0 {
            signals.append(Signal(
                icon: "arrow.down.circle.fill",
                title: "Drawdown exceeds total profit",
                detail: "\(metrics.maxDrawdown.asCurrency) max DD vs \(metrics.totalProfit.asCurrency) total P&L. Tighten stops.",
                value: nil,
                color: .semanticAmber,
                priority: 0
            ))
        }

        // High Sharpe — positive reinforcement
        if metrics.sharpeRatio >= 1.5 {
            signals.append(Signal(
                icon: "chart.line.uptrend.xyaxis",
                title: "Excellent risk-adjusted returns",
                detail: "Sharpe ratio \(String(format: "%.2f", metrics.sharpeRatio)) — your consistency is strong.",
                value: String(format: "%.2f", metrics.sharpeRatio),
                color: .semanticGreen,
                priority: 4
            ))
        }

        return signals.sorted { $0.priority < $1.priority }
    }
}
