import SwiftUI

/// Compares current period metrics vs previous period
struct PeriodComparison: View {
    let trades: [Trade]

    @State private var selectedPeriod: Period = .month

    enum Period: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case quarter = "Quarter"

        var id: String { rawValue }

        var daysBack: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    private var currentPeriodTrades: [Trade] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.daysBack, to: Date()) ?? Date()
        return trades.filter { $0.closeTime >= cutoff }
    }

    private var previousPeriodTrades: [Trade] {
        let currentCutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.daysBack, to: Date()) ?? Date()
        let previousCutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.daysBack * 2, to: Date()) ?? Date()
        return trades.filter { $0.closeTime >= previousCutoff && $0.closeTime < currentCutoff }
    }

    private struct ComparisonMetric: Identifiable {
        let id: String
        let label: String
        let current: String
        let previous: String
        let change: Double
        let isPositiveGood: Bool
    }

    private var comparisons: [ComparisonMetric] {
        let current = MetricsCalculator.calculate(from: currentPeriodTrades)
        let previous = MetricsCalculator.calculate(from: previousPeriodTrades)

        return [
            ComparisonMetric(
                id: "pnl", label: "P&L",
                current: current.totalProfit.asCompactCurrency,
                previous: previous.totalProfit.asCompactCurrency,
                change: percentChange(current.totalProfit, previous.totalProfit),
                isPositiveGood: true
            ),
            ComparisonMetric(
                id: "wr", label: "Win Rate",
                current: current.winRate.asPercent,
                previous: previous.winRate.asPercent,
                change: current.winRate - previous.winRate,
                isPositiveGood: true
            ),
            ComparisonMetric(
                id: "pf", label: "Profit Factor",
                current: current.profitFactor.asProfitFactor,
                previous: previous.profitFactor.asProfitFactor,
                change: percentChange(current.profitFactor, previous.profitFactor),
                isPositiveGood: true
            ),
            ComparisonMetric(
                id: "avgr", label: "Avg R",
                current: current.averageRMultiple.asRMultiple,
                previous: previous.averageRMultiple.asRMultiple,
                change: current.averageRMultiple - previous.averageRMultiple,
                isPositiveGood: true
            ),
            ComparisonMetric(
                id: "trades", label: "Trades",
                current: "\(current.totalTrades)",
                previous: "\(previous.totalTrades)",
                change: percentChange(Double(current.totalTrades), Double(previous.totalTrades)),
                isPositiveGood: true
            ),
            ComparisonMetric(
                id: "dd", label: "Max DD",
                current: current.maxDrawdown.asCompactCurrency,
                previous: previous.maxDrawdown.asCompactCurrency,
                change: percentChange(current.maxDrawdown, previous.maxDrawdown),
                isPositiveGood: false
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon + title + period pills
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticBlueDim)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.smallText)
                                .foregroundStyle(Color.semanticBlue)
                        )
                    Text("Period Comparison")
                        .font(.cardTitle)
                }
                Spacer()

                // Custom pill selector
                HStack(spacing: 0) {
                    ForEach(Period.allCases) { period in
                        periodPill(period)
                    }
                }
            }

            if currentPeriodTrades.isEmpty && previousPeriodTrades.isEmpty {
                Text("No trades in selected periods")
                    .font(.sidebarItem)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                // Table
                VStack(spacing: 0) {
                    // Header row
                    tableHeaderRow

                    // Data rows
                    ForEach(Array(comparisons.enumerated()), id: \.element.id) { index, metric in
                        tableRow(metric, isEven: index % 2 == 1)
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

    // MARK: - Period Pill

    private func periodPill(_ period: Period) -> some View {
        let isSelected = selectedPeriod == period
        return Text(period.rawValue)
            .font(.sidebarItem)
            .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentDim : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected
                            ? Color.accent.opacity(0.2)
                            : Color.borderCard,
                        lineWidth: 1
                    )
            )
            .onTapGesture { selectedPeriod = period }
    }

    // MARK: - Table Header

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 80, alignment: .leading)
            Text("CURRENT")
                .frame(maxWidth: .infinity)
            Text("PREVIOUS")
                .frame(maxWidth: .infinity)
            Text("CHANGE")
                .frame(maxWidth: .infinity)
        }
        .font(.smallText)
        .tracking(0.5)
        .foregroundStyle(Color.textTertiary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)
        }
    }

    // MARK: - Table Row

    private func tableRow(_ metric: ComparisonMetric, isEven: Bool) -> some View {
        HStack(spacing: 0) {
            // Label
            Text(metric.label)
                .font(.sidebarItem)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, alignment: .leading)

            // Current value
            Text(metric.current)
                .font(.sidebarItem)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)

            // Previous value
            Text(previousPeriodTrades.isEmpty ? "–" : metric.previous)
                .font(.sidebarItem)
                .foregroundStyle(previousPeriodTrades.isEmpty ? Color.textTertiary : Color.textSecondary)
                .frame(maxWidth: .infinity)

            // Change indicator
            changeCell(metric)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(isEven ? Color.bgInset : Color.clear)
    }

    // MARK: - Change Cell

    @ViewBuilder
    private func changeCell(_ metric: ComparisonMetric) -> some View {
        if previousPeriodTrades.isEmpty {
            Text("–")
                .font(.sidebarItem)
                .foregroundStyle(Color.textTertiary)
        } else {
            let isGood = metric.isPositiveGood ? metric.change > 0 : metric.change < 0
            let isBad = metric.isPositiveGood ? metric.change < 0 : metric.change > 0
            let color = isGood ? Color.semanticGreen : isBad ? Color.semanticRed : Color.textTertiary

            HStack(spacing: 3) {
                Image(systemName: metric.change > 0 ? "arrow.up" : metric.change < 0 ? "arrow.down" : "minus")
                    .font(.monoSmall)
                Text(String(format: "%.1f", abs(metric.change)) + (metric.id == "wr" || metric.id == "avgr" ? "" : "%"))
                    .font(.sidebarItem)
            }
            .foregroundStyle(color)
        }
    }

    // MARK: - Helpers

    private func percentChange(_ current: Double, _ previous: Double) -> Double {
        guard previous != 0 else { return current > 0 ? 100 : current < 0 ? -100 : 0 }
        return (current - previous) / abs(previous) * 100
    }
}
