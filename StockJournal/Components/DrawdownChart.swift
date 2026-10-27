import SwiftUI
import Charts

/// Displays the portfolio drawdown over time as an area chart
struct DrawdownChart: View {
    let trades: [Trade]

    private var drawdownData: [(date: Date, drawdown: Double)] {
        guard !trades.isEmpty else { return [] }

        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        var cumulative = 0.0
        var peak = 0.0
        var data: [(date: Date, drawdown: Double)] = []

        for trade in sorted {
            cumulative += trade.profitDouble
            peak = max(peak, cumulative)
            let drawdown = cumulative - peak // Always <= 0
            data.append((date: trade.closeTime, drawdown: drawdown))
        }
        return data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Drawdown")
                    .font(.cardTitle)
                Spacer()
                if let maxDD = drawdownData.map(\.drawdown).min() {
                    Text("Max: \(maxDD.asCurrency)")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticRed)
                }
            }

            if drawdownData.isEmpty {
                Text("Import trades to see drawdown chart")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(Array(drawdownData.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Drawdown", point.drawdown)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.semanticRed.opacity(0.4), Color.semanticRed.opacity(0.05)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Drawdown", point.drawdown)
                        )
                        .foregroundStyle(Color.semanticRed.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
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
                .frame(height: 140)
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
