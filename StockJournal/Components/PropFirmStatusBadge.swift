import SwiftUI

/// Compact prop firm status for Dashboard Overview — shows ON TRACK/BREACHED + daily P&L + progress
/// Tapping navigates to the full Prop Firm tracker
struct PropFirmStatusBadge: View {
    let trades: [Trade]
    @Environment(\.appState) private var appState
    @State private var isHovered = false

    /// Read from the encrypted journal when the badge appears (`PropFirmSettings`)
    @State private var settings = PropFirmSettings()

    private var accountSize: Double { settings.accountSize }
    private var maxDailyLossPercent: Double { settings.maxDailyLoss }
    private var maxDrawdownPercent: Double { settings.maxTotalDrawdown }
    private var profitTargetPercent: Double { settings.profitTarget }

    private var totalPnL: Double {
        trades.reduce(0) { $0 + $1.profitDouble }
    }

    private var dailyPnL: Double {
        PropFirmTracker.todayPnL(trades, now: Date())
    }

    private var maxDailyLossDollars: Double {
        accountSize * (maxDailyLossPercent / 100)
    }

    private var maxDrawdownDollars: Double {
        accountSize * (maxDrawdownPercent / 100)
    }

    private var profitTargetDollars: Double {
        accountSize * (profitTargetPercent / 100)
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

    private var drawdownBreached: Bool {
        maxDrawdown > maxDrawdownDollars
    }

    private var isBreached: Bool {
        dailyLossBreached || drawdownBreached
    }

    private var profitProgress: Double {
        guard profitTargetDollars > 0 else { return 0 }
        return min(max(totalPnL / profitTargetDollars, 0), 1)
    }

    private var dailyLossUsed: Double {
        guard maxDailyLossDollars > 0 else { return 0 }
        return min(abs(min(dailyPnL, 0)) / maxDailyLossDollars, 1)
    }

    /// Warning level for daily loss: .none, .caution (75%+), .danger (90%+), .breached (100%+)
    private enum WarningLevel {
        case none, caution, danger, breached
    }

    private var dailyLossWarning: WarningLevel {
        if dailyLossBreached { return .breached }
        if dailyLossUsed >= 0.90 { return .danger }
        if dailyLossUsed >= 0.75 { return .caution }
        return .none
    }

    /// Color for the daily loss gauge based on warning level
    private var dailyLossGaugeColor: Color {
        switch dailyLossWarning {
        case .none: Color.accent
        case .caution: Color.semanticAmber
        case .danger: Color.semanticRed
        case .breached: Color.semanticRed
        }
    }

    @ViewBuilder
    var body: some View {
        if !trades.isEmpty {
        Button {
            appState.selectedDashboardCategory = .propFirm
        } label: {
        HStack(spacing: 12) {
            // Icon + label
            HStack(spacing: 6) {
                Image(systemName: "building.columns")
                    .font(.smallText)
                    .foregroundStyle(Color.accent)
                Text("Prop Firm")
                    .font(.sidebarItem)
                    .foregroundStyle(Color.textSecondary)
            }

            // Status badge — escalates from ON TRACK → CAUTION → DANGER → BREACHED
            switch dailyLossWarning {
            case .breached:
                statusBadge("BREACHED", color: .semanticRed, bg: .semanticRedDim)
            case .danger:
                statusBadge("DANGER", color: .semanticRed, bg: .semanticRedDim)
            case .caution:
                statusBadge("CAUTION", color: .semanticAmber, bg: .semanticAmberDim)
            case .none:
                if drawdownBreached {
                    statusBadge("BREACHED", color: .semanticRed, bg: .semanticRedDim)
                } else {
                    statusBadge("ON TRACK", color: .semanticGreen, bg: .semanticGreenDim)
                }
            }

            Spacer()

            // Today's P&L
            VStack(alignment: .trailing, spacing: 1) {
                Text("Today")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)
                Text(dailyPnL.asCurrency)
                    .font(.monoSubtitle)
                    .foregroundStyle(dailyPnL == 0 ? Color.textSecondary : Color.forPnL(dailyPnL))
            }

            // Daily loss gauge
            VStack(alignment: .trailing, spacing: 1) {
                Text("Daily Limit")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.borderSubtle)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(dailyLossGaugeColor)
                                .frame(width: max(geo.size.width * dailyLossUsed, 0), height: 4)
                        }
                    }
                    .frame(width: 48, height: 4)
                    Text(String(format: "%.0f%%", dailyLossUsed * 100))
                        .font(.monoSmall)
                        .fontWeight(dailyLossWarning == .danger || dailyLossWarning == .breached ? .bold : .regular)
                        .foregroundStyle(dailyLossGaugeColor)
                }
            }

            // Profit progress
            VStack(alignment: .trailing, spacing: 1) {
                Text("Target")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.borderSubtle)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.semanticGreen)
                                .frame(width: max(geo.size.width * profitProgress, 0), height: 4)
                        }
                    }
                    .frame(width: 48, height: 4)
                    Text(String(format: "%.0f%%", profitProgress * 100))
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary.opacity(isHovered ? 0.8 : 0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.bgCard.opacity(0.8) : Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accent.opacity(0.3) : Color.borderCard, lineWidth: 1)
        )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help("View full Prop Firm Tracker")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prop Firm: \(isBreached ? "Breached" : dailyLossWarning == .danger ? "Danger" : dailyLossWarning == .caution ? "Caution" : "On Track"). Today: \(dailyPnL.asCurrency). Daily limit used: \(String(format: "%.0f%%", dailyLossUsed * 100)). Target progress: \(String(format: "%.0f%%", profitProgress * 100))")
        .accessibilityAddTraits(.isButton)
        .onAppear { settings = PropFirmSettings.load(from: appState.database) }
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ text: String, color: Color, bg: Color) -> some View {
        Text(text)
            .font(.monoSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
