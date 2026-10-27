import SwiftUI

/// Shows optimal trading hours based on historical P&L — groups adjacent profitable/unprofitable hours into named windows
struct KillZoneOptimizer: View {
    let trades: [Trade]
    @State private var exportToast: ToastData?

    // MARK: - Types

    private struct HourStats {
        let hour: Int, pnl: Double, count: Int, winRate: Double
    }

    private struct TimeWindow: Identifiable {
        let id = UUID()
        let startHour: Int, endHour: Int
        let pnl: Double, count: Int, winRate: Double, monthlyImpact: Double
        var label: String { String(format: "%02d-%02d ET", startHour, endHour + 1) }
    }

    // MARK: - Computed Properties

    private var tradingDays: Int {
        max(TradingCalendar.tradingDayCount(trades), 1)
    }

    private var hourlyStats: [HourStats] {
        let grouped = Dictionary(grouping: trades) { $0.hour }
        return (0..<24).map { hour in
            let hourTrades = grouped[hour] ?? []
            let pnl = hourTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = hourTrades.filter(\.isWin).count
            let wr = hourTrades.isEmpty ? 0 : Double(wins) / Double(hourTrades.count) * 100
            return HourStats(hour: hour, pnl: pnl, count: hourTrades.count, winRate: wr)
        }
    }

    private var recommendWindows: [TimeWindow] { buildWindows(profitable: true) }
    private var avoidWindows: [TimeWindow] { buildWindows(profitable: false) }

    private var topWindowMonthlyPnL: Double { recommendWindows.reduce(0.0) { $0 + $1.monthlyImpact } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !MetricsCalculator.isActionable(sampleSize: trades.count) {
                insufficientData
            } else {
                timeline
                if !recommendWindows.isEmpty { windowSection("Recommended Windows", windows: recommendWindows, positive: true) }
                if !avoidWindows.isEmpty { windowSection("Avoid Windows", windows: avoidWindows, positive: false) }
                if !recommendWindows.isEmpty { bottomInsight }
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

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Label("Kill Zone Optimizer", systemImage: "clock.arrow.2.circlepath")
                .font(.cardTitle)
            Spacer()
            if MetricsCalculator.isActionable(sampleSize: trades.count) {
                Button { exportCSV() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Export kill zones to CSV")
            }
            ConfidenceBadge(sampleSize: trades.count)
        }
    }

    private var insufficientData: some View {
        Text("Need at least 30 trades for kill zone analysis")
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 1) {
                ForEach(hourlyStats, id: \.hour) { stat in
                    Rectangle()
                        .fill(timelineColor(for: stat))
                        .frame(height: 14)
                        .help("\(stat.hour):00 — \(stat.pnl.asCompactCurrency) (\(stat.count) trades)")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack {
                Text("0:00")
                Spacer()
                Text("6:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("18:00")
                Spacer()
                Text("24:00")
            }
            .font(.monoSmall)
            .foregroundStyle(Color.textTertiary)
        }
    }

    private func windowSection(_ title: String, windows: [TimeWindow], positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: positive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(positive ? Color.semanticGreen : Color.semanticRed)
                    .font(.smallText)
                Text(title)
                    .font(.smallText)
                    .fontWeight(.semibold)
            }

            ForEach(windows) { window in
                windowRow(window, positive: positive)
            }
        }
    }

    private func windowRow(_ window: TimeWindow, positive: Bool) -> some View {
        HStack(spacing: 12) {
            Text(window.label)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(window.pnl.asCompactCurrency)
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(window.pnl))

            Text(String(format: "%.0f%%", window.winRate))
                .font(.monoSubtitle)

            Text("\(window.count)t")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)

            Text(window.monthlyImpact.asCompactCurrency + "/mo")
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(window.monthlyImpact))

            ConfidenceBadge(sampleSize: window.count, compact: true)
        }
        .lineLimit(1)
    }

    private var bottomInsight: some View {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb.fill")
                .font(.smallText)
                .foregroundStyle(.yellow)
            Text("Trading only your top windows would have produced ")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            + Text(topWindowMonthlyPnL.asCurrency + "/month")
                .font(.smallText)
                .foregroundColor(Color.forPnL(topWindowMonthlyPnL))
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func exportCSV() {
        var rows = [["Type", "Window", "P&L", "Win Rate", "Trades", "Monthly Impact"]]
        for (type, windows) in [("Recommend", recommendWindows), ("Avoid", avoidWindows)] {
            for w in windows {
                rows.append([type, w.label, String(format: "%.2f", w.pnl), String(format: "%.1f", w.winRate),
                             String(w.count), String(format: "%.2f", w.monthlyImpact)])
            }
        }
        rows.append([])
        rows.append(["Hour", "P&L", "Trades", "Win Rate"])
        for stat in hourlyStats where stat.count > 0 {
            rows.append(["\(stat.hour):00", String(format: "%.2f", stat.pnl), String(stat.count),
                         String(format: "%.1f", stat.winRate)])
        }
        let name = "KillZones_\(Date().formatted(.iso8601.year().month().day())).csv"
        do {
            if try AnalyticsCSV.save(rows, suggestedName: name) != nil {
                exportToast = ToastData(style: .success, message: "Kill zones exported")
            }
        } catch {
            exportToast = ToastData(style: .error, message: "Export failed: \(error.localizedDescription)")
        }
    }

    private func timelineColor(for stat: HourStats) -> Color {
        guard stat.count >= 10 else { return Color.textTertiary.opacity(0.3) }
        return stat.pnl >= 0 ? Color.semanticGreen.opacity(0.7) : Color.semanticRed.opacity(0.7)
    }

    private func buildWindows(profitable: Bool) -> [TimeWindow] {
        let qualifying = hourlyStats.filter { stat in
            stat.count >= 10 && (profitable ? stat.pnl > 0 : stat.pnl < 0)
        }
        guard !qualifying.isEmpty else { return [] }

        let monthScale = 21.0 / Double(tradingDays)
        var windows: [TimeWindow] = []
        var current: [HourStats] = []

        for stat in hourlyStats {
            let qualifies = stat.count >= 10 && (profitable ? stat.pnl > 0 : stat.pnl < 0)
            if qualifies {
                current.append(stat)
            } else if !current.isEmpty {
                if let window = makeWindow(from: current, monthScale: monthScale) {
                    windows.append(window)
                }
                current = []
            }
        }
        if !current.isEmpty {
            if let window = makeWindow(from: current, monthScale: monthScale) {
                windows.append(window)
            }
        }

        return windows.sorted { abs($0.pnl) > abs($1.pnl) }
    }

    private func makeWindow(from hours: [HourStats], monthScale: Double) -> TimeWindow? {
        guard let first = hours.first, let last = hours.last else { return nil }
        let pnl = hours.reduce(0.0) { $0 + $1.pnl }
        let count = hours.reduce(0) { $0 + $1.count }
        let wins = hours.reduce(0.0) { $0 + $1.winRate * Double($1.count) }
        let wr = count > 0 ? wins / Double(count) : 0

        return TimeWindow(
            startHour: first.hour,
            endHour: last.hour,
            pnl: pnl,
            count: count,
            winRate: wr,
            monthlyImpact: pnl * monthScale
        )
    }
}
