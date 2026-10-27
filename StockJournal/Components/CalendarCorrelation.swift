import SwiftUI
import Charts

/// Retrospective analysis: correlates trade performance with known high-impact economic events
/// Uses recurring event patterns (NFP, FOMC, etc.) since historical calendar data isn't stored
struct CalendarCorrelation: View {
    let trades: [Trade]

    private var analysis: EventAnalysis {
        analyze(trades)
    }

    var body: some View {
        if trades.count < 20 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("News Correlation", systemImage: "newspaper")
                        .font(.smallText)
                        .fontWeight(.bold)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(analysis.eventDayTrades.count) event-day trades")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }

                // Comparison chart
                comparisonChart

                // Key stats
                statsGrid

                // Event type breakdown
                if !analysis.eventBreakdown.isEmpty {
                    eventBreakdown
                }

                // Insight
                insightBanner
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        }
    }

    // MARK: - Comparison Chart

    private var comparisonChart: some View {
        let data: [(label: String, metric: String, value: Double)] = [
            ("Event Days", "Win Rate", analysis.eventDayWinRate * 100),
            ("Quiet Days", "Win Rate", analysis.quietDayWinRate * 100),
            ("Event Days", "Avg P&L", analysis.eventDayAvgPnL),
            ("Quiet Days", "Avg P&L", analysis.quietDayAvgPnL),
            ("Event Days", "Avg R", analysis.eventDayAvgR),
            ("Quiet Days", "Avg R", analysis.quietDayAvgR),
        ]

        return Chart(data, id: \.label) { item in
            if item.metric == "Win Rate" {
                BarMark(
                    x: .value("Metric", item.metric),
                    y: .value("Value", item.value),
                    width: .ratio(0.35)
                )
                .foregroundStyle(item.label == "Event Days" ? Color.orange : Color.accent)
                .position(by: .value("Type", item.label))
            }
        }
        .chartYAxisLabel("Win Rate %")
        .chartLegend(position: .top, alignment: .trailing)
        .frame(height: 120)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard(
                title: "EVENT DAYS",
                winRate: analysis.eventDayWinRate,
                avgPnL: analysis.eventDayAvgPnL,
                count: analysis.eventDayTrades.count,
                color: .orange
            )
            statCard(
                title: "QUIET DAYS",
                winRate: analysis.quietDayWinRate,
                avgPnL: analysis.quietDayAvgPnL,
                count: analysis.quietDayTrades.count,
                color: Color.accent
            )
        }
    }

    private func statCard(title: String, winRate: Double, avgPnL: Double, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.monoSubtitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win Rate")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.0f%%", winRate * 100))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg P&L")
                        .font(.monoSmall)
                        .foregroundStyle(Color.textTertiary)
                    Text(String(format: "%+.2f", avgPnL))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.forPnL(avgPnL))
                }
            }
            Text("\(count) trades")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(8)
        .background(Color.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    // MARK: - Event Breakdown

    private var eventBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BY EVENT TYPE")
                .font(.monoSubtitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)

            ForEach(analysis.eventBreakdown.sorted(by: { $0.value.count > $1.value.count }).prefix(5), id: \.key) { event, stats in
                HStack {
                    Text(event)
                        .font(.smallText)
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    Spacer()
                    Text("\(stats.count)")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 24)
                    Text(String(format: "%.0f%%", stats.winRate * 100))
                        .font(.monoSubtitle)
                        .foregroundStyle(stats.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                        .frame(width: 34)
                    Text(String(format: "%+.2f", stats.avgPnL))
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.forPnL(stats.avgPnL))
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Insight

    private var insightBanner: some View {
        let diff = analysis.quietDayAvgPnL - analysis.eventDayAvgPnL
        let betterOn = diff > 0 ? "quiet" : "event"
        let amount = abs(diff)

        return HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.smallText)
                .foregroundStyle(.yellow)
            Text(amount < 1 ? "Your performance is similar on event and quiet days." :
                    "You average $\(String(format: "%.2f", amount)) more per trade on \(betterOn) days.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    // MARK: - Analysis

    struct EventStats {
        var count: Int = 0
        var wins: Int = 0
        var totalPnL: Double = 0
        var winRate: Double { count > 0 ? Double(wins) / Double(count) : 0 }
        var avgPnL: Double { count > 0 ? totalPnL / Double(count) : 0 }
    }

    struct EventAnalysis {
        var eventDayTrades: [Trade] = []
        var quietDayTrades: [Trade] = []
        var eventBreakdown: [String: EventStats] = [:]

        var eventDayWinRate: Double {
            eventDayTrades.isEmpty ? 0 : Double(eventDayTrades.filter(\.isWin).count) / Double(eventDayTrades.count)
        }
        var quietDayWinRate: Double {
            quietDayTrades.isEmpty ? 0 : Double(quietDayTrades.filter(\.isWin).count) / Double(quietDayTrades.count)
        }
        var eventDayAvgPnL: Double {
            eventDayTrades.isEmpty ? 0 : eventDayTrades.map(\.profitDouble).reduce(0, +) / Double(eventDayTrades.count)
        }
        var quietDayAvgPnL: Double {
            quietDayTrades.isEmpty ? 0 : quietDayTrades.map(\.profitDouble).reduce(0, +) / Double(quietDayTrades.count)
        }
        var eventDayAvgR: Double {
            let rs = eventDayTrades.filter { $0.rMultiple != 0 }
            return rs.isEmpty ? 0 : rs.map(\.rMultiple).reduce(0, +) / Double(rs.count)
        }
        var quietDayAvgR: Double {
            let rs = quietDayTrades.filter { $0.rMultiple != 0 }
            return rs.isEmpty ? 0 : rs.map(\.rMultiple).reduce(0, +) / Double(rs.count)
        }
    }

    private func analyze(_ trades: [Trade]) -> EventAnalysis {
        var result = EventAnalysis()

        for trade in trades {
            let events = knownEventsForDate(trade.openTime)
            if events.isEmpty {
                result.quietDayTrades.append(trade)
            } else {
                result.eventDayTrades.append(trade)
                for event in events {
                    var stats = result.eventBreakdown[event] ?? EventStats()
                    stats.count += 1
                    if trade.isWin { stats.wins += 1 }
                    stats.totalPnL += trade.profitDouble
                    result.eventBreakdown[event] = stats
                }
            }
        }

        return result
    }

    /// Identify known recurring high-impact events based on date patterns
    /// This is a heuristic — it won't catch every event, but covers the major recurring ones
    private func knownEventsForDate(_ date: Date) -> [String] {
        // US market events are scheduled in Eastern time
        let components = TradingCalendar.calendar.dateComponents([.weekday, .weekOfMonth, .day, .month, .hour], from: date)
        let weekday = components.weekday ?? 0
        let weekOfMonth = components.weekOfMonth ?? 0
        let day = components.day ?? 0
        let month = components.month ?? 0
        let hour = components.hour ?? 0

        var events: [String] = []

        // NFP: First Friday of the month, typically 8:30 AM ET
        if weekday == 6 && weekOfMonth == 1 {
            events.append("NFP (Non-Farm Payrolls)")
        }

        // FOMC: ~8 times per year, typically Wed. We approximate: Jan, Mar, May, Jun, Jul, Sep, Nov, Dec
        // Typically 2:00 PM ET on a Wednesday
        let fomcMonths: Set<Int> = [1, 3, 5, 6, 7, 9, 11, 12]
        if weekday == 4 && fomcMonths.contains(month) && (day >= 15 && day <= 28) {
            events.append("FOMC")
        }

        // CPI: Typically second week of month, Tue/Wed
        if (weekday == 3 || weekday == 4) && (day >= 10 && day <= 14) {
            events.append("CPI Release")
        }

        // Monday (often risk-off / gap day)
        if weekday == 2 && hour < 10 {
            events.append("Monday Open")
        }

        // Friday afternoon (reduced liquidity)
        if weekday == 6 && hour >= 15 {
            events.append("Friday Close")
        }

        return events
    }
}
