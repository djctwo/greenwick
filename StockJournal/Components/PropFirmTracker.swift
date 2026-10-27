import SwiftUI

/// Prop firm challenge progress tracker
struct PropFirmTracker: View {
    let trades: [Trade]
    @Environment(\.appState) private var appState
    @State private var accountSize: Double = 100_000
    @State private var profitTarget: Double = 8.0  // percent
    @State private var maxDailyLoss: Double = 5.0  // percent
    @State private var maxTotalDrawdown: Double = 10.0  // percent
    @State private var hasLoaded = false

    // Inline editing state
    @State private var editingField: EditField?
    @State private var editText: String = ""

    private enum EditField: Hashable {
        case account, target, dailyLoss, drawdown
    }

    private var totalPnL: Double {
        trades.reduce(0) { $0 + $1.profitDouble }
    }

    private var currentBalance: Double {
        accountSize + totalPnL
    }

    private var profitTargetDollars: Double {
        accountSize * (profitTarget / 100)
    }

    private var maxDailyLossDollars: Double {
        accountSize * (maxDailyLoss / 100)
    }

    private var maxDrawdownDollars: Double {
        accountSize * (maxTotalDrawdown / 100)
    }

    private var dailyPnL: Double {
        Self.todayPnL(trades, now: Date())
    }

    private var maxDrawdown: Double {
        var peak: Double = 0
        var maxDD: Double = 0
        var cumulative: Double = 0

        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        for trade in sorted {
            cumulative += trade.profitDouble
            if cumulative > peak { peak = cumulative }
            let dd = peak - cumulative
            if dd > maxDD { maxDD = dd }
        }
        return maxDD
    }

    private var dailyLossBreached: Bool {
        abs(dailyPnL) > maxDailyLossDollars && dailyPnL < 0
    }

    private var dailyLossUsedPercent: Double {
        guard maxDailyLossDollars > 0 else { return 0 }
        return min(abs(min(dailyPnL, 0)) / maxDailyLossDollars, 1)
    }

    /// Dynamic color for daily loss — escalates from accent → amber → red
    private var dailyLossColor: Color {
        if dailyLossBreached { return Color.semanticRed }
        if dailyLossUsedPercent >= 0.90 { return Color.semanticRed }
        if dailyLossUsedPercent >= 0.75 { return Color.semanticAmber }
        return Color.accent
    }

    private var drawdownBreached: Bool {
        maxDrawdown > maxDrawdownDollars
    }

    private var tradingDays: Int {
        Self.tradingDayCount(trades)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticAmberDim)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "building.columns")
                                .font(.smallText)
                                .foregroundStyle(Color.accent)
                        )
                    Text("Prop Firm Tracker")
                        .font(.cardTitle)
                }
                Spacer()

                if dailyLossBreached || drawdownBreached {
                    Text("LIMIT BREACHED")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.semanticRedDim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if dailyLossUsedPercent >= 0.90 {
                    Text("DANGER")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.semanticRedDim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if dailyLossUsedPercent >= 0.75 {
                    Text("CAUTION")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticAmber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.semanticAmberDim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("ON TRACK")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.semanticGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.semanticGreenDim)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Top metrics row: Account, Balance, Days, Today
            HStack(spacing: 0) {
                propMetric(
                    label: "ACCOUNT",
                    value: accountSize.asCurrency,
                    field: .account
                )
                propMetric(
                    label: "BALANCE",
                    value: currentBalance.asCurrency,
                    color: Color.forPnL(totalPnL)
                )
                propMetric(
                    label: "DAYS",
                    value: "\(tradingDays)"
                )
                propMetric(
                    label: "TODAY",
                    value: dailyPnL.asCurrency,
                    color: dailyPnL == 0 ? Color.textPrimary : Color.forPnL(dailyPnL)
                )
            }

            // Progress bars
            VStack(spacing: 14) {
                progressRow(
                    title: "Profit Target",
                    current: max(totalPnL, 0),
                    target: profitTargetDollars,
                    color: Color.semanticGreen
                )
                progressRow(
                    title: "Daily Loss Limit",
                    current: abs(min(dailyPnL, 0)),
                    target: maxDailyLossDollars,
                    color: dailyLossColor
                )
                progressRow(
                    title: "Max Drawdown",
                    current: maxDrawdown,
                    target: maxDrawdownDollars,
                    color: drawdownBreached ? Color.semanticRed : Color.semanticRed.opacity(0.7)
                )
            }

            // Bottom config row (hidden — preserved for future use)
            if false {
                Rectangle()
                    .fill(Color.borderSubtle)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    propMetric(
                        label: "PROFIT TARGET",
                        value: String(format: "%.1f%%", profitTarget),
                        field: .target
                    )
                    propMetric(
                        label: "MAX DAILY LOSS",
                        value: String(format: "%.1f%%", maxDailyLoss),
                        field: .dailyLoss
                    )
                    propMetric(
                        label: "MAX DRAWDOWN",
                        value: String(format: "%.1f%%", maxTotalDrawdown),
                        field: .drawdown
                    )
                    propMetric(
                        label: "TOTAL P&L",
                        value: totalPnL.asCurrency,
                        color: Color.forPnL(totalPnL)
                    )
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
        .onAppear { loadSettings() }
    }

    // MARK: - Metric Cell

    @ViewBuilder
    private func propMetric(
        label: String,
        value: String,
        color: Color = Color.textPrimary,
        field: EditField? = nil
    ) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.monoSubtitle)
                .tracking(0.5)
                .foregroundStyle(Color.textTertiary)

            if let field, editingField == field {
                TextField("", text: $editText)
                    .font(.bodyText)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(width: 80)
                    .onSubmit { commitEdit(field) }
            } else {
                Text(value)
                    .font(.bodyText)
                    .foregroundStyle(color)
                    .onTapGesture {
                        if let field {
                            startEditing(field)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Progress Row

    private func progressRow(
        title: String,
        current: Double,
        target: Double,
        color: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.sidebarItem)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(current.asCurrency) / \(target.asCurrency)")
                    .font(.sidebarItem)
                    .foregroundStyle(Color.textSecondary)
            }

            GeometryReader { geo in
                let progress = target > 0 ? min(max(current / target, 0), 1) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.semanticAmber.opacity(0.05))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, 0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Inline Editing

    private func startEditing(_ field: EditField) {
        editingField = field
        switch field {
        case .account: editText = String(format: "%.0f", accountSize)
        case .target: editText = String(format: "%.1f", profitTarget)
        case .dailyLoss: editText = String(format: "%.1f", maxDailyLoss)
        case .drawdown: editText = String(format: "%.1f", maxTotalDrawdown)
        }
    }

    private func commitEdit(_ field: EditField) {
        guard let val = Double(editText) else {
            editingField = nil
            return
        }
        switch field {
        case .account: accountSize = val
        case .target: profitTarget = val
        case .dailyLoss: maxDailyLoss = val
        case .drawdown: maxTotalDrawdown = val
        }
        editingField = nil
        saveSettings()
    }

    // MARK: - Persistence

    /// Kept in the encrypted journal (`PropFirmSettings`), never in the preferences file
    private func loadSettings() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let saved = PropFirmSettings.load(from: appState.database)
        accountSize = saved.accountSize
        profitTarget = saved.profitTarget
        maxDailyLoss = saved.maxDailyLoss
        maxTotalDrawdown = saved.maxTotalDrawdown
    }

    private func saveSettings() {
        let settings = PropFirmSettings(accountSize: accountSize, profitTarget: profitTarget,
                                        maxDailyLoss: maxDailyLoss, maxTotalDrawdown: maxTotalDrawdown)
        do {
            try settings.save(to: appState.database)
        } catch {
            appState.showToast(.error, "Couldn't save the prop firm settings: \(error.localizedDescription)")
        }
        // Show what was stored (out-of-range entries fall back to the defaults)
        let stored = settings.sanitized()
        accountSize = stored.accountSize
        profitTarget = stored.profitTarget
        maxDailyLoss = stored.maxDailyLoss
        maxTotalDrawdown = stored.maxTotalDrawdown
    }
}

extension PropFirmTracker {
    /// Net P&L of trades closed on today's US trading day (the New York date of `now`) —
    /// what the daily loss limit is measured against
    static func todayPnL(_ trades: [Trade], now: Date) -> Double {
        TradingCalendar.pnl(onTradingDayOf: now, trades)
    }

    /// Number of distinct US trading days with at least one closed trade
    static func tradingDayCount(_ trades: [Trade]) -> Int {
        TradingCalendar.tradingDayCount(trades)
    }
}
