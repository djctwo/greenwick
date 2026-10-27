import SwiftUI

/// Reconstructs the intraday P&L curve to show WHEN during the day profits are made/lost
struct IntradayEquityCurve: View {
    let trades: [Trade]

    // MARK: - Data Models

    private struct HourBucket: Identifiable {
        let id: Int // hour
        let hour: Int
        let avgPnL: Double
        let tradeCount: Int
        let cumulativePnL: Double
    }

    // MARK: - Computed Data

    /// Market hours: 9 (covers 9:30) through 15 (last full hour before close)
    private static let marketHours = Array(9...15)

    private var hourBuckets: [HourBucket] {
        let grouped = Dictionary(grouping: trades) { $0.hour }
        var cumulative = 0.0
        var buckets: [HourBucket] = []

        for hour in Self.marketHours {
            let hourTrades = grouped[hour] ?? []
            let avg = hourTrades.isEmpty
                ? 0
                : hourTrades.map(\.profitDouble).reduce(0, +) / Double(hourTrades.count)
            cumulative += avg
            buckets.append(HourBucket(
                id: hour,
                hour: hour,
                avgPnL: avg,
                tradeCount: hourTrades.count,
                cumulativePnL: cumulative
            ))
        }

        return buckets
    }

    private var morningPnL: Double {
        // 9:30-12:00 → hours 9, 10, 11
        let grouped = Dictionary(grouping: trades) { $0.hour }
        return (9...11).reduce(0.0) { total, hour in
            let hourTrades = grouped[hour] ?? []
            return total + hourTrades.map(\.profitDouble).reduce(0, +)
        }
    }

    private var afternoonPnL: Double {
        // 12:00-16:00 → hours 12, 13, 14, 15
        let grouped = Dictionary(grouping: trades) { $0.hour }
        return (12...15).reduce(0.0) { total, hour in
            let hourTrades = grouped[hour] ?? []
            return total + hourTrades.map(\.profitDouble).reduce(0, +)
        }
    }

    private var insightText: String {
        if morningPnL > 0 && afternoonPnL < 0 {
            return "You make money in the morning and give it back after lunch"
        } else if morningPnL < 0 && afternoonPnL > 0 {
            return "Slow start but your edge is strongest in the afternoon"
        } else if morningPnL > 0 && afternoonPnL > 0 {
            let stronger = morningPnL > afternoonPnL ? "morning" : "afternoon"
            return "Profitable all day -- \(stronger) is your strongest session"
        } else {
            return "Negative P&L across both sessions -- review trade selection"
        }
    }

    // MARK: - Chart Geometry

    private var maxAbsCumulative: Double {
        let values = hourBuckets.map(\.cumulativePnL)
        let absMax = values.map { abs($0) }.max() ?? 1
        return max(absMax, 1) // prevent division by zero
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Intraday P&L Pattern", systemImage: "chart.line.uptrend.xyaxis")
                .font(.cardTitle)

            if trades.count < 10 {
                Text("Need at least 10 trades for intraday analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if hourBuckets.allSatisfy({ $0.tradeCount == 0 }) {
                Text("No trades during regular market hours")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                cumulativePnLChart
                statsRow
                insightBanner
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

    // MARK: - Cumulative P&L Line Chart (Custom Path)

    private var cumulativePnLChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVG CUMULATIVE P&L BY HOUR")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .tracking(0.5)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let midY = height / 2
                let buckets = hourBuckets
                let pointCount = buckets.count

                ZStack {
                    // Zero line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: midY))
                        path.addLine(to: CGPoint(x: width, y: midY))
                    }
                    .stroke(Color.borderCard, style: StrokeStyle(lineWidth: 0.5, dash: [4]))

                    if pointCount > 1 {
                        // Shaded area — positive green, negative red
                        positiveArea(buckets: buckets, width: width, height: height, midY: midY)
                        negativeArea(buckets: buckets, width: width, height: height, midY: midY)

                        // Line
                        Path { path in
                            for (idx, bucket) in buckets.enumerated() {
                                let x = xPosition(index: idx, count: pointCount, width: width)
                                let y = yPosition(value: bucket.cumulativePnL, height: height, midY: midY)
                                if idx == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Dots
                        ForEach(buckets) { bucket in
                            let idx = buckets.firstIndex(where: { $0.id == bucket.id }) ?? 0
                            let x = xPosition(index: idx, count: pointCount, width: width)
                            let y = yPosition(value: bucket.cumulativePnL, height: height, midY: midY)

                            Circle()
                                .fill(bucket.cumulativePnL >= 0 ? Color.semanticGreen : Color.semanticRed)
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }

                    // Hour labels along bottom
                    ForEach(buckets) { bucket in
                        let idx = buckets.firstIndex(where: { $0.id == bucket.id }) ?? 0
                        let x = xPosition(index: idx, count: pointCount, width: width)

                        Text(hourLabel(bucket.hour))
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)
                            .position(x: x, y: height - 2)
                    }
                }
            }
            .frame(height: 140)
        }
    }

    // MARK: - Shaded Areas

    private func positiveArea(buckets: [HourBucket], width: CGFloat, height: CGFloat, midY: CGFloat) -> some View {
        Path { path in
            let count = buckets.count
            guard count > 1 else { return }

            path.move(to: CGPoint(x: xPosition(index: 0, count: count, width: width), y: midY))

            for (idx, bucket) in buckets.enumerated() {
                let x = xPosition(index: idx, count: count, width: width)
                let y = yPosition(value: max(0, bucket.cumulativePnL), height: height, midY: midY)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(
                x: xPosition(index: count - 1, count: count, width: width),
                y: midY
            ))
            path.closeSubpath()
        }
        .fill(Color.semanticGreen.opacity(0.15))
    }

    private func negativeArea(buckets: [HourBucket], width: CGFloat, height: CGFloat, midY: CGFloat) -> some View {
        Path { path in
            let count = buckets.count
            guard count > 1 else { return }

            path.move(to: CGPoint(x: xPosition(index: 0, count: count, width: width), y: midY))

            for (idx, bucket) in buckets.enumerated() {
                let x = xPosition(index: idx, count: count, width: width)
                let y = yPosition(value: min(0, bucket.cumulativePnL), height: height, midY: midY)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(
                x: xPosition(index: count - 1, count: count, width: width),
                y: midY
            ))
            path.closeSubpath()
        }
        .fill(Color.semanticRed.opacity(0.15))
    }

    // MARK: - Positioning Helpers

    private func xPosition(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        let padding: CGFloat = 20
        let usableWidth = width - padding * 2
        return padding + usableWidth * CGFloat(index) / CGFloat(count - 1)
    }

    private func yPosition(value: Double, height: CGFloat, midY: CGFloat) -> CGFloat {
        // Leave 16px for bottom labels
        let chartHeight = height - 16
        let chartMidY = chartHeight / 2
        let normalized = CGFloat(value / maxAbsCumulative)
        return chartMidY - normalized * (chartHeight / 2 - 8)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 9 { return "9:30" }
        return "\(hour):00"
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
            statItem(
                "Morning (9:30-12:00)",
                morningPnL.asCompactCurrency,
                color: Color.forPnL(morningPnL)
            )
            Divider().frame(height: 28)
            statItem(
                "Afternoon (12:00-16:00)",
                afternoonPnL.asCompactCurrency,
                color: Color.forPnL(afternoonPnL)
            )
            Spacer()
        }
    }

    private func statItem(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Insight

    private var insightBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb.fill")
                .font(.smallText)
                .foregroundStyle(Color.semanticAmber)
            Text(insightText)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
