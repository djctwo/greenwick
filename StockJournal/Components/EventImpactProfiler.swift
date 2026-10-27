import SwiftUI

/// Institutional-level analysis of how recurring economic events impact trading performance.
/// Profiles each event type (NFP, FOMC, CPI, Earnings, Jobs Report) with timing analysis,
/// per-symbol impact, and actionable trade/skip recommendations.
struct EventImpactProfiler: View {
    let trades: [Trade]

    private var results: [EventTypeResult] { analyzeByEventType(trades) }

    var body: some View {
        if trades.count < 30 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                header

                if results.isEmpty {
                    Text("Not enough event-day trades for analysis")
                        .font(.bodyText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    eventVsQuietSummary

                    ForEach(results) { result in
                        eventTypeRow(result)
                    }

                    if results.contains(where: { !$0.preTrades.isEmpty || !$0.postTrades.isEmpty }) {
                        timingBreakdown
                    }

                    symbolImpact
                    insightBanner
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticRedDim)
                        .frame(width: 22, height: 22)
                    Image(systemName: "newspaper.fill")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticRed)
                }
                Text("Event Impact Profiler")
                    .font(.cardTitle)
            }
            Spacer()
            let eventCount = results.flatMap(\.trades).count
            ConfidenceBadge(sampleSize: eventCount, compact: true)
        }
    }

    // MARK: - Event vs Quiet Summary

    private var eventVsQuietSummary: some View {
        let allEvent = results.flatMap(\.trades)
        let eventIDs = Set(allEvent.map(\.ticket))
        let quiet = trades.filter { !eventIDs.contains($0.ticket) }

        return HStack(spacing: 12) {
            miniStatCard(
                title: "EVENT DAYS", trades: allEvent,
                color: Color.semanticAmber
            )
            miniStatCard(
                title: "QUIET DAYS", trades: quiet,
                color: Color.accent
            )
        }
    }

    // MARK: - Event Type Rows

    private func eventTypeRow(_ result: EventTypeResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(result.recommendation.dimColor)
                    .frame(width: 28, height: 28)
                Image(systemName: result.eventType.icon)
                    .font(.sidebarItem)
                    .foregroundStyle(result.recommendation.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.eventType.rawValue)
                    .font(.sidebarItem)
                Text("\(result.trades.count) trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            metricColumn(
                String(format: "%.0f%%", result.winRate * 100), label: "WR",
                color: result.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed,
                width: 40
            )
            metricColumn(
                String(format: "%+.2f", result.avgPnL), label: "Avg",
                color: Color.forPnL(result.avgPnL),
                width: 55
            )
            metricColumn(
                String(format: "%.2f", result.profitFactor), label: "PF",
                color: result.profitFactor >= 1.0 ? Color.semanticGreen : Color.semanticRed,
                width: 40
            )

            Text(result.recommendation.rawValue)
                .font(.monoSubtitle)
                .foregroundStyle(result.recommendation.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(result.recommendation.dimColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            ConfidenceBadge(sampleSize: result.trades.count, compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    private func metricColumn(_ value: String, label: String, color: Color, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(color)
            Text(label)
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: width)
    }

    // MARK: - Timing Breakdown

    private var timingBreakdown: some View {
        let allPre = results.flatMap(\.preTrades)
        let allDuring = results.flatMap(\.duringTrades)
        let allPost = results.flatMap(\.postTrades)

        return VStack(alignment: .leading, spacing: 8) {
            Text("TIMING ANALYSIS")
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 8) {
                timingCard("Pre-Event", trades: allPre, icon: "arrow.right", color: Color.semanticBlue)
                timingCard("During", trades: allDuring, icon: "bolt.fill", color: Color.semanticAmber)
                timingCard("Post-Event", trades: allPost, icon: "arrow.left", color: Color.semanticPurple)
            }
        }
    }

    private func timingCard(_ title: String, trades: [Trade], icon: String, color: Color) -> some View {
        let winRate = trades.isEmpty ? 0 : Double(trades.filter(\.isWin).count) / Double(trades.count)
        let avgPnL = trades.isEmpty ? 0 : trades.map(\.profitDouble).reduce(0, +) / Double(trades.count)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.monoSmall).foregroundStyle(color)
                Text(title).font(.smallText).fontWeight(.bold).foregroundStyle(Color.textSecondary)
            }

            if trades.isEmpty {
                Text("–")
                    .font(.kpiValueSecondary)
                    .foregroundStyle(Color.textTertiary)
                Text(" ")
                    .font(.monoSubtitle)
                Text(" ")
                    .font(.monoSmall)
            } else {
                Text(String(format: "%.0f%%", winRate * 100))
                    .font(.kpiValueSecondary)
                    .foregroundStyle(winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                Text(String(format: "%+.2f avg", avgPnL))
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(avgPnL))
                Text("\(trades.count)")
                    .font(.monoSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Symbol Impact

    @ViewBuilder
    private var symbolImpact: some View {
        let allEvent = results.flatMap(\.trades)
        let eventBySymbol = Dictionary(grouping: allEvent, by: \.symbol)
        let overallBySymbol = Dictionary(grouping: trades, by: \.symbol)

        let rows: [(symbol: String, eventWR: Double, normalWR: Double, delta: Double, count: Int)] =
            eventBySymbol.compactMap { symbol, eventTrades in
                guard eventTrades.count >= 5 else { return nil }
                let ewr = Double(eventTrades.filter(\.isWin).count) / Double(eventTrades.count)
                let normalTrades = overallBySymbol[symbol] ?? []
                let nwr = normalTrades.isEmpty ? 0 : Double(normalTrades.filter(\.isWin).count) / Double(normalTrades.count)
                return (symbol, ewr, nwr, ewr - nwr, eventTrades.count)
            }
            .sorted { abs($0.delta) > abs($1.delta) }

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYMBOL IMPACT DURING EVENTS")
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textSecondary)

                ForEach(rows.prefix(5), id: \.symbol) { row in
                    HStack {
                        Text(row.symbol)
                            .font(.monoSubtitle)
                            .frame(width: 70, alignment: .leading)

                        Text(String(format: "%.0f%%", row.normalWR * 100))
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 35)

                        Image(systemName: "arrow.right")
                            .font(.monoSmall)
                            .foregroundStyle(Color.textTertiary)

                        Text(String(format: "%.0f%%", row.eventWR * 100))
                            .font(.monoSubtitle)
                            .foregroundStyle(row.eventWR >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                            .frame(width: 35)

                        Spacer()

                        Text(String(format: "%+.0f%%", row.delta * 100))
                            .font(.monoSubtitle)
                            .foregroundStyle(row.delta >= 0 ? Color.semanticGreen : Color.semanticRed)

                        Text("(\(row.count))")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Insight

    private var insightBanner: some View {
        let worst = results.filter { $0.trades.count >= 5 && $0.avgPnL < 0 }
            .min(by: { $0.avgPnL < $1.avgPnL })
        let best = results.filter { $0.trades.count >= 5 && $0.avgPnL > 0 }
            .max(by: { $0.avgPnL < $1.avgPnL })

        let text: String
        if let worst = worst, worst.trades.count >= 10 {
            let months = max(1, tradingMonths)
            let monthlyCost = abs(worst.totalPnL) / Double(months)
            text = "Skipping \(worst.eventType.rawValue) could save ~$\(String(format: "%.0f", monthlyCost))/month (\(worst.trades.count) trades at $\(String(format: "%.2f", worst.avgPnL)) avg)."
        } else if let best = best {
            text = "Best event: \(best.eventType.rawValue) — \(String(format: "%.0f%%", best.winRate * 100)) WR, $\(String(format: "+%.2f", best.avgPnL)) avg per trade."
        } else {
            text = "Need more event-day trades for a recommendation. Keep trading and check back."
        }

        return HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.smallText)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Mini Stat Card

    private func miniStatCard(title: String, trades: [Trade], color: Color) -> some View {
        let wr = trades.isEmpty ? 0 : Double(trades.filter(\.isWin).count) / Double(trades.count)
        let avg = trades.isEmpty ? 0 : trades.map(\.profitDouble).reduce(0, +) / Double(trades.count)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win Rate").font(.monoSmall).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.0f%%", wr * 100))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(wr >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg P&L").font(.monoSmall).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%+.2f", avg))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.forPnL(avg))
                }
            }
            Text("\(trades.count) trades")
                .font(.monoSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(8)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Analysis Engine

    private var tradingMonths: Int {
        guard let first = trades.min(by: { $0.openTime < $1.openTime })?.openTime else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1
        return max(1, days / 30)
    }

    private func analyzeByEventType(_ trades: [Trade]) -> [EventTypeResult] {
        EventType.allCases.compactMap { eventType in
            let matching = trades.filter { matchesEvent($0, eventType: eventType) }
            guard matching.count >= 3 else { return nil }

            let winCount = matching.filter(\.isWin).count
            let winRate = Double(winCount) / Double(matching.count)
            let totalPnL = matching.map(\.profitDouble).reduce(0, +)
            let avgPnL = totalPnL / Double(matching.count)

            let rs = matching.filter { $0.rMultiple != 0 }
            let avgR = rs.isEmpty ? 0 : rs.map(\.rMultiple).reduce(0, +) / Double(rs.count)

            let grossWin = matching.filter(\.isWin).map(\.profitDouble).reduce(0, +)
            let grossLoss = abs(matching.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
            let pf = grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? 99.0 : 0)

            let eventHour = eventType.typicalHourET
            let pre = matching.filter { $0.hour >= eventHour - 2 && $0.hour < eventHour }
            let during = matching.filter { $0.hour == eventHour || $0.hour == eventHour + 1 }
            let post = matching.filter { $0.hour > eventHour + 1 && $0.hour <= eventHour + 3 }

            let rec: Recommendation
            if matching.count >= 10 {
                if winRate >= 0.55 && pf >= 1.2 { rec = .trade }
                else if winRate < 0.40 || pf < 0.8 { rec = .avoid }
                else { rec = .caution }
            } else {
                rec = .caution
            }

            return EventTypeResult(
                eventType: eventType, trades: matching, winRate: winRate,
                avgPnL: avgPnL, avgR: avgR, totalPnL: totalPnL, profitFactor: pf,
                recommendation: rec, preTrades: pre, duringTrades: during, postTrades: post
            )
        }
        .sorted { $0.trades.count > $1.trades.count }
    }

    // MARK: - Event Matching Heuristics

    private func matchesEvent(_ trade: Trade, eventType: EventType) -> Bool {
        // US releases are scheduled in Eastern time, not the user's
        let c = TradingCalendar.calendar.dateComponents([.weekday, .weekOfMonth, .day, .month, .hour], from: trade.openTime)
        let wd = c.weekday ?? 0, wom = c.weekOfMonth ?? 0
        let day = c.day ?? 0, month = c.month ?? 0, hour = c.hour ?? 0

        switch eventType {
        case .nfp:
            return wd == 6 && wom == 1
        case .fomc:
            return wd == 4 && [1, 3, 5, 6, 7, 9, 11, 12].contains(month) && (15...28).contains(day)
        case .cpi:
            return (wd == 3 || wd == 4) && (10...14).contains(day)
        case .earnings:
            // Proxy: trades around typical earnings release windows (after market close)
            return hour >= 16 && hour <= 18
        case .jobsReport:
            // Proxy: first Friday of the month (BLS release)
            return wd == 6 && wom == 1 && (8...14).contains(hour)
        case .mondayOpen:
            return wd == 2 && hour < 9
        case .fridayClose:
            return wd == 6 && hour >= 18
        }
    }
}

// MARK: - Models

extension EventImpactProfiler {
    enum EventType: String, CaseIterable, Identifiable {
        case nfp = "NFP"
        case fomc = "FOMC"
        case cpi = "CPI"
        case earnings = "Earnings"
        case jobsReport = "Jobs Report"
        case mondayOpen = "Mon Open"
        case fridayClose = "Fri Close"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .nfp: "person.3.fill"
            case .fomc: "building.columns.fill"
            case .cpi: "chart.line.uptrend.xyaxis"
            case .earnings: "doc.text.fill"
            case .jobsReport: "briefcase.fill"
            case .mondayOpen: "sunrise.fill"
            case .fridayClose: "sunset.fill"
            }
        }

        /// Typical release hour in ET
        var typicalHourET: Int {
            switch self {
            case .nfp: 8          // 8:30 AM ET
            case .fomc: 14        // 2:00 PM ET
            case .cpi: 8          // 8:30 AM ET
            case .earnings: 16    // After market close
            case .jobsReport: 8   // 8:30 AM ET
            case .mondayOpen: 9   // Opening bell
            case .fridayClose: 15 // Last regular hour
            }
        }

        var affectedSectors: [String] {
            switch self {
            case .nfp, .fomc, .cpi, .jobsReport: ["All"]
            case .earnings: ["Reporting"]
            case .mondayOpen, .fridayClose: []
            }
        }
    }

    enum Recommendation: String {
        case trade = "TRADE"
        case caution = "CAUTION"
        case avoid = "AVOID"

        var color: Color {
            switch self {
            case .trade: Color.semanticGreen
            case .caution: Color.semanticAmber
            case .avoid: Color.semanticRed
            }
        }

        var dimColor: Color {
            switch self {
            case .trade: Color.semanticGreenDim
            case .caution: Color.semanticAmberDim
            case .avoid: Color.semanticRedDim
            }
        }
    }

    struct EventTypeResult: Identifiable {
        let eventType: EventType
        let trades: [Trade]
        let winRate: Double
        let avgPnL: Double
        let avgR: Double
        let totalPnL: Double
        let profitFactor: Double
        let recommendation: Recommendation
        let preTrades: [Trade]
        let duringTrades: [Trade]
        let postTrades: [Trade]

        var id: String { eventType.rawValue }
    }
}
