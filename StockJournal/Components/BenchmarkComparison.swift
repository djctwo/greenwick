import SwiftUI

/// Compares trader performance against industry benchmarks
struct BenchmarkComparison: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    private struct Benchmark {
        let label: String
        let value: Double
        let format: Format

        enum Format {
            case percent, currency, ratio, multiple
        }
    }

    private var comparisons: [(metric: String, yours: String, benchmark: String, status: Status)] {
        guard metrics.totalTrades >= 10 else { return [] }

        return [
            comparison(
                metric: "Win Rate",
                yours: metrics.winRate,
                benchmark: 45.0,
                format: { String(format: "%.1f%%", $0) },
                betterWhen: .higher
            ),
            comparison(
                metric: "Profit Factor",
                yours: metrics.profitFactor,
                benchmark: 1.3,
                format: { String(format: "%.2f", $0) },
                betterWhen: .higher
            ),
            comparison(
                metric: "Avg R-Multiple",
                yours: metrics.averageRMultiple,
                benchmark: 0.3,
                format: { String(format: "%.2fR", $0) },
                betterWhen: .higher
            ),
            comparison(
                metric: "Sharpe Ratio",
                yours: metrics.sharpeRatio,
                benchmark: 0.5,
                format: { String(format: "%.2f", $0) },
                betterWhen: .higher
            ),
            comparison(
                metric: "Max Drawdown %",
                yours: metrics.maxDrawdown / max(abs(metrics.totalProfit), 1) * 100,
                benchmark: 30.0,
                format: { String(format: "%.0f%%", $0) },
                betterWhen: .lower
            ),
        ]
    }

    enum Status {
        case above, at, below

        var color: Color {
            switch self {
            case .above: Color.semanticGreen
            case .at: .secondary
            case .below: Color.semanticRed
            }
        }

        var icon: String {
            switch self {
            case .above: "chevron.up.circle.fill"
            case .at: "minus.circle"
            case .below: "chevron.down.circle.fill"
            }
        }
    }

    enum Direction { case higher, lower }

    private func comparison(
        metric: String,
        yours: Double,
        benchmark: Double,
        format: (Double) -> String,
        betterWhen: Direction
    ) -> (metric: String, yours: String, benchmark: String, status: Status) {
        let threshold = benchmark * 0.1
        let diff = yours - benchmark
        let status: Status
        switch betterWhen {
        case .higher:
            status = diff > threshold ? .above : diff < -threshold ? .below : .at
        case .lower:
            status = diff < -threshold ? .above : diff > threshold ? .below : .at
        }
        return (metric: metric, yours: format(yours), benchmark: format(benchmark), status: status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("vs Benchmarks", systemImage: "chart.bar.doc.horizontal")
                    .font(.cardTitle)
                Spacer()
                Text("Retail average")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            if comparisons.isEmpty {
                Text("Need 10+ trades for benchmark comparison")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Header
                HStack {
                    Text("Metric")
                        .frame(width: 100, alignment: .leading)
                    Text("You")
                        .frame(width: 65)
                    Text("Avg")
                        .frame(width: 65)
                    Text("")
                        .frame(width: 28)
                }
                .font(.smallText)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)

                ForEach(comparisons, id: \.metric) { item in
                    HStack {
                        Text(item.metric)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 100, alignment: .leading)

                        Text(item.yours)
                            .font(.monoSubtitle)
                            .fontWeight(.semibold)
                            .frame(width: 65)

                        Text(item.benchmark)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 65)

                        Image(systemName: item.status.icon)
                            .foregroundStyle(item.status.color)
                            .font(.smallText)
                            .frame(width: 28)
                    }
                }

                // Summary
                let aboveCount = comparisons.filter { $0.status == .above }.count
                let total = comparisons.count
                HStack(spacing: 4) {
                    Text("Above average in \(aboveCount)/\(total) metrics")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
    }
}
