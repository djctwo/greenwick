import SwiftUI
import Charts

/// Projects expected equity growth based on current edge metrics
struct ExpectancyCurve: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    private var projectionPoints: [(trade: Int, actual: Double, projected: Double)] {
        guard trades.count >= 10, metrics.expectancy != 0 else { return [] }

        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        var cumulative = 0.0
        var points: [(trade: Int, actual: Double, projected: Double)] = []

        for (i, trade) in sorted.enumerated() {
            cumulative += trade.profitDouble
            let projected = metrics.expectancy * Double(i + 1)
            points.append((trade: i + 1, actual: cumulative, projected: projected))
        }

        return points
    }

    private var deviation: String {
        guard let last = projectionPoints.last else { return "—" }
        let diff = last.actual - last.projected
        let pct = last.projected != 0 ? diff / abs(last.projected) * 100 : 0
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f%%", pct)) vs expected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Expectancy Curve", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.cardTitle)
                Spacer()
                Text(deviation)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            if projectionPoints.isEmpty {
                Text("Need 10+ trades to project expectancy")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart {
                    ForEach(projectionPoints, id: \.trade) { point in
                        LineMark(
                            x: .value("Trade #", point.trade),
                            y: .value("P&L", point.actual)
                        )
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    ForEach(projectionPoints, id: \.trade) { point in
                        LineMark(
                            x: .value("Trade #", point.trade),
                            y: .value("Expected", point.projected)
                        )
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    }

                    // Zero line
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Actual": Color.accent,
                    "Expected": Color.secondary.opacity(0.5),
                ])
                .frame(height: 200)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.accent)
                            .frame(width: 16, height: 2)
                        Text("Actual")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 16, height: 2)
                        Text("Expected (\(metrics.expectancy.asCurrency)/trade)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
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
}
