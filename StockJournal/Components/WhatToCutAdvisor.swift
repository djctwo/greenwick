import SwiftUI

/// Identifies ALL negative-expectancy trading conditions across every dimension
/// and tells the trader what to STOP doing, with exact dollar amounts.
struct WhatToCutAdvisor: View {
    let trades: [Trade]
    @State private var exportToast: ToastData?

    // MARK: - Computed Properties

    private var tradingDays: Int {
        max(TradingCalendar.tradingDayCount(trades), 1)
    }

    private var negativeConditions: [MetricsCalculator.EdgeCondition] {
        MetricsCalculator.allEdgeConditions(from: trades, tradingDays: tradingDays)
            .filter { $0.expectancy < 0 && $0.tradeCount >= 10 }
            .sorted { $0.monthlyImpact < $1.monthlyImpact }
    }

    private var totalPotentialSavings: Double {
        negativeConditions.reduce(0.0) { $0 + $1.monthlyImpact }
    }

    private var worstCondition: MetricsCalculator.EdgeCondition? {
        negativeConditions.first
    }

    private var hasEnoughData: Bool {
        trades.count >= 30
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !hasEnoughData {
                insufficientDataView
            } else if negativeConditions.isEmpty {
                cleanSlateView
            } else {
                savingsBanner
                conditionsTable
                bottomInsight
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    .toast($exportToast)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("What to Cut", systemImage: "scissors")
                .font(.cardTitle)
            Spacer()
            if hasEnoughData && !negativeConditions.isEmpty {
                Button { exportCSV() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Export negative conditions to CSV")
            }
        }
    }

    // MARK: - Empty States

    private var insufficientDataView: some View {
        Text("Need at least 30 trades to identify patterns worth cutting.")
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var cleanSlateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.kpiValueSecondary)
                .foregroundStyle(Color.semanticGreen)
            Text("No negative-expectancy conditions found with 10+ trades.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: - Savings Banner

    private var savingsBanner: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Total Potential Savings")
                    .font(.smallText)
                    .fontWeight(.bold)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(abs(totalPotentialSavings).asCurrency)
                    .font(.cardTitle)
                    .foregroundStyle(Color.semanticRed)
                Text("/mo")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }
            Text("Conditions may overlap \u{2014} actual savings will be lower than the sum.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(10)
        .background(Color.semanticRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    // MARK: - Conditions Table

    private var conditionsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            ForEach(negativeConditions) { condition in
                conditionRow(condition)
                if condition.id != negativeConditions.last?.id {
                    Divider()
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6) {
            Text("")
                .frame(width: 16)
            Text("Condition")
                .frame(minWidth: 80, alignment: .leading)
            Spacer()
            Text("Monthly")
                .frame(width: 70, alignment: .trailing)
            Text("Trades")
                .frame(width: 44, alignment: .trailing)
            Text("")
                .frame(width: 16)
        }
        .font(.smallText)
        .fontWeight(.bold)
        .foregroundStyle(Color.textSecondary)
        .padding(.vertical, 4)
    }

    private func conditionRow(_ condition: MetricsCalculator.EdgeCondition) -> some View {
        HStack(spacing: 6) {
            Image(systemName: condition.dimensionIcon)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 16)

            Text(condition.label)
                .font(.smallText)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)

            Spacer()

            Text(condition.monthlyImpact.asCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.semanticRed)
                .frame(width: 70, alignment: .trailing)

            Text("\(condition.tradeCount)")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .trailing)

            ConfidenceBadge(sampleSize: condition.tradeCount, compact: true)
                .frame(width: 16)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bottom Insight

    private func exportCSV() {
        let name = "WhatToCut_\(Date().formatted(.iso8601.year().month().day())).csv"
        do {
            if try AnalyticsCSV.save(Self.csvRows(negativeConditions, totalSavings: totalPotentialSavings),
                                     suggestedName: name) != nil {
                exportToast = ToastData(style: .success, message: "What to Cut exported")
            }
        } catch {
            exportToast = ToastData(style: .error, message: "Export failed: \(error.localizedDescription)")
        }
    }

    /// The exported table (header first)
    nonisolated static func csvRows(_ conditions: [MetricsCalculator.EdgeCondition], totalSavings: Double) -> [[String]] {
        var rows = [["Dimension", "Condition", "P&L", "Win Rate", "Trades", "Expectancy", "Profit Factor",
                     "Monthly Impact"]]
        for c in conditions {
            rows.append([c.dimension, c.label, String(format: "%.2f", c.profit), String(format: "%.1f", c.winRate),
                         String(c.tradeCount), String(format: "%.2f", c.expectancy),
                         String(format: "%.2f", c.profitFactor), String(format: "%.2f", c.monthlyImpact)])
        }
        rows.append([])
        rows.append(["Total Potential Savings (monthly)", String(format: "%.2f", totalSavings)])
        return rows
    }

    @ViewBuilder
    private var bottomInsight: some View {
        if let worst = worstCondition {
            Divider()
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.smallText)
                    .foregroundStyle(.orange)
                Text("Your single biggest improvement: stop ")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                + Text(worst.label)
                    .font(.smallText)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                + Text(" to save ~\(abs(worst.monthlyImpact).asCurrency)/month.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
