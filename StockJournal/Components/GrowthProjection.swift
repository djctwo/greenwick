import SwiftUI
import Charts

/// Projects account growth based on current trade frequency and expectancy
struct GrowthProjection: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    @State private var months = 6

    private var tradesPerWeek: Double {
        guard trades.count >= 5 else { return 0 }
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        guard let first = sorted.first?.closeTime, let last = sorted.last?.closeTime else { return 0 }
        let weeks = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1) / 7
        return weeks > 0 ? Double(trades.count) / Double(weeks) : Double(trades.count)
    }

    private var projectionData: [(week: Int, conservative: Double, expected: Double, optimistic: Double)] {
        guard metrics.expectancy > 0, tradesPerWeek > 0 else { return [] }

        let totalWeeks = months * 4
        let weeklyExpected = metrics.expectancy * tradesPerWeek
        var points: [(week: Int, conservative: Double, expected: Double, optimistic: Double)] = []

        for w in 0...totalWeeks {
            let expected = weeklyExpected * Double(w)
            let conservative = expected * 0.6
            let optimistic = expected * 1.4
            points.append((week: w, conservative: conservative, expected: expected, optimistic: optimistic))
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Growth Projection", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.cardTitle)
                Spacer()
                Picker("Months", selection: $months) {
                    Text("3mo").tag(3)
                    Text("6mo").tag(6)
                    Text("12mo").tag(12)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if projectionData.isEmpty {
                VStack(spacing: 4) {
                    Text("Insufficient data for projection")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                    if metrics.expectancy <= 0 {
                        Text("Positive expectancy required for growth projections")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart {
                    // Optimistic band
                    ForEach(projectionData, id: \.week) { point in
                        AreaMark(
                            x: .value("Week", point.week),
                            yStart: .value("Low", point.conservative),
                            yEnd: .value("High", point.optimistic)
                        )
                        .foregroundStyle(Color.accent.opacity(0.1))
                    }

                    // Expected line
                    ForEach(projectionData, id: \.week) { point in
                        LineMark(
                            x: .value("Week", point.week),
                            y: .value("Expected", point.expected)
                        )
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
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
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("W\(v)")
                            }
                        }
                    }
                }
                .frame(height: 200)

                // Stats
                HStack(spacing: 20) {
                    statPill("Trades/week", String(format: "%.1f", tradesPerWeek))
                    statPill("Exp/trade", metrics.expectancy.asCurrency)
                    if let last = projectionData.last {
                        statPill("\(months)mo target", last.expected.asCompactCurrency)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }

    private func statPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
