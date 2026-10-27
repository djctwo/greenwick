import SwiftUI

/// Side-by-side comparison of best and worst trades
struct TradeComparison: View {
    let trades: [Trade]

    private var bestTrade: Trade? {
        trades.max(by: { $0.profitDouble < $1.profitDouble })
    }

    private var worstTrade: Trade? {
        trades.min(by: { $0.profitDouble < $1.profitDouble })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best vs Worst Trade")
                .font(.cardTitle)

            if let best = bestTrade, let worst = worstTrade {
                HStack(alignment: .top, spacing: 16) {
                    tradeCard(trade: best, title: "Best Trade", color: .semanticGreen)
                    tradeCard(trade: worst, title: "Worst Trade", color: .semanticRed)
                }
            } else {
                Text("Need at least 1 trade")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
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

    private func tradeCard(trade: Trade, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Spacer()
                Text(trade.profitDouble.asCurrency)
                    .font(.monoSubtitle)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            Divider()

            comparisonRow("Symbol", trade.tickerDisplay)
            comparisonRow("Direction", trade.direction.rawValue)
            comparisonRow("Session", trade.session.displayName)
            comparisonRow("Hour", "\(trade.hour):00 ET")
            comparisonRow("R-Multiple", trade.rMultiple.asRMultiple)
            comparisonRow("Duration", "\(trade.durationMin) min")
            comparisonRow("MAE", trade.maePoints.asPoints)
            comparisonRow("MFE", trade.mfePoints.asPoints)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func comparisonRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.monoSubtitle)
        }
    }
}
