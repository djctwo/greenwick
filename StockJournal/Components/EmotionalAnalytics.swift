import SwiftUI
import Charts

/// "Tiltmeter" — correlates pre-trade emotional state with trading performance.
/// Requires minimum 10 trades with emotions tagged.
struct EmotionalAnalytics: View {
    let trades: [Trade]

    // MARK: - Data Model

    private struct EmotionMetric: Identifiable {
        let id: TradeEmotion
        let emotion: TradeEmotion
        let count: Int
        let wins: Int
        let totalPnL: Double
        var winRate: Double { count > 0 ? Double(wins) / Double(count) : 0 }
        var avgPnL: Double { count > 0 ? totalPnL / Double(count) : 0 }
    }

    // MARK: - Analysis

    private var metrics: [EmotionMetric]? {
        let tagged = trades.filter { $0.tradeEmotion != nil }
        guard tagged.count >= 10 else { return nil }

        var grouped: [TradeEmotion: (count: Int, wins: Int, pnl: Double)] = [:]
        for trade in tagged {
            guard let emotion = trade.tradeEmotion else { continue }
            var entry = grouped[emotion, default: (0, 0, 0)]
            entry.count += 1
            if trade.isWin { entry.wins += 1 }
            entry.pnl += trade.profitDouble
            grouped[emotion] = entry
        }

        return grouped.map { emotion, data in
            EmotionMetric(id: emotion, emotion: emotion, count: data.count, wins: data.wins, totalPnL: data.pnl)
        }.sorted { $0.avgPnL > $1.avgPnL }
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tiltmeter", systemImage: "brain.head.profile.fill")
                .font(.cardTitle)

            if let metrics, let best = metrics.first, let worst = metrics.last, metrics.count > 1 {
                // Bar chart — avg P&L per emotion
                Chart(metrics) { metric in
                    BarMark(
                        x: .value("Emotion", metric.emotion.displayName),
                        y: .value("Avg P&L", metric.avgPnL)
                    )
                    .foregroundStyle(Color.forPnL(metric.avgPnL))
                    .annotation(position: metric.avgPnL >= 0 ? .top : .bottom, spacing: 2) {
                        Text(metric.avgPnL.asCurrency)
                            .font(.monoSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.monoSmall)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.smallText)
                    }
                }
                .frame(height: 140)

                // Insight banner
                VStack(alignment: .leading, spacing: 4) {
                    if best.avgPnL > 0 {
                        insightRow(
                            icon: "checkmark.circle.fill",
                            color: .semanticGreen,
                            text: "Your best emotional state is \(best.emotion.displayName) (+\(best.avgPnL.asCurrency) avg)"
                        )
                    }
                    if worst.avgPnL < 0 {
                        insightRow(
                            icon: "exclamationmark.triangle.fill",
                            color: .semanticRed,
                            text: "Avoid trading when \(worst.emotion.displayName) (\(worst.avgPnL.asCurrency) avg)"
                        )
                    }
                }

                // Per-emotion grid
                VStack(spacing: 0) {
                    headerRow
                    ForEach(metrics) { metric in
                        emotionRow(metric)
                    }
                }
            } else {
                Text("Need at least 10 emotion-tagged trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Subviews

    private func insightRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.smallText)
                .foregroundStyle(color)
            Text(text)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Emotion")
                .frame(width: 100, alignment: .leading)
            Text("Trades")
                .frame(width: 50, alignment: .trailing)
            Text("Win %")
                .frame(width: 55, alignment: .trailing)
            Text("Avg P&L")
                .frame(width: 70, alignment: .trailing)
            Text("Total P&L")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.smallText)
        .foregroundStyle(Color.textSecondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func emotionRow(_ metric: EmotionMetric) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: metric.emotion.icon)
                    .font(.smallText)
                    .foregroundStyle(colorForName(metric.emotion.color))
                Text(metric.emotion.displayName)
                    .font(.smallText)
            }
            .frame(width: 100, alignment: .leading)

            Text("\(metric.count)")
                .font(.monoSubtitle)
                .frame(width: 50, alignment: .trailing)

            Text("\(Int(saturating: metric.winRate * 100))%")
                .font(.monoSubtitle)
                .foregroundStyle(metric.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                .frame(width: 55, alignment: .trailing)

            Text(metric.avgPnL.asCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(metric.avgPnL))
                .frame(width: 70, alignment: .trailing)

            Text(metric.totalPnL.asCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(metric.totalPnL))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "green": Color.semanticGreen
        case "blue": Color.semanticBlue
        case "yellow": .yellow
        case "orange": .orange
        case "red": Color.semanticRed
        case "purple": Color.semanticPurple
        case "gray": .gray
        default: .secondary
        }
    }
}
