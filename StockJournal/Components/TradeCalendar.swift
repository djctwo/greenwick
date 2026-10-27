import SwiftUI

/// Calendar view showing daily P&L with color-coded cells.
///
/// Days are US trading days (New York dates, `TradingCalendar`), so an after-hours trade
/// closed Friday 18:50 ET sits on Friday wherever the user lives. "Today" is the New York date.
struct TradeCalendar: View {
    let trades: [Trade]

    @State private var selectedMonth: Date = Date()

    private var calendar: Calendar { Self.gridCalendar() }

    private var dailyPnL: [Date: Double] { Self.dailyPnL(for: trades) }

    private var daysInMonth: [Date] { Self.days(inMonthOf: selectedMonth, calendar: calendar) }

    private var firstWeekdayOffset: Int { Self.leadingBlankCount(for: daysInMonth, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("P&L Calendar")
                    .font(.cardTitle)
                Spacer()

                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(Self.monthTitle(selectedMonth))
                    .font(.smallText)
                    .fontWeight(.medium)
                    .frame(width: 140)

                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Self.weekdayHeaders(calendar: calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.smallText)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                // Empty cells for offset
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 32)
                }

                // Day cells
                ForEach(daysInMonth, id: \.self) { date in
                    dayCell(date: date)
                }
            }

            // Monthly total
            let monthTotal = daysInMonth.reduce(0.0) { $0 + (dailyPnL[$1] ?? 0) }
            let tradeDays = daysInMonth.filter { dailyPnL[$0] != nil }.count
            HStack {
                Text("\(tradeDays) trading days")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Month: \(monthTotal.asCurrency)")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.forPnL(monthTotal))
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

    private func dayCell(date: Date) -> some View {
        let pnl = dailyPnL[calendar.startOfDay(for: date)]
        let dayNum = calendar.component(.day, from: date)
        let isToday = Self.isToday(date, now: Date(), calendar: calendar)

        return VStack(spacing: 1) {
            Text("\(dayNum)")
                .font(.smallText)
                .fontWeight(isToday ? .bold : .regular)

            if let pnl {
                Text(pnl.asCompactCurrency)
                    .font(.monoSmall)
                    .foregroundStyle(Color.forPnL(pnl))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(cellBackground(pnl: pnl, isToday: isToday))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func cellBackground(pnl: Double?, isToday: Bool) -> some View {
        Group {
            if let pnl {
                if pnl > 0 {
                    Color.semanticGreen.opacity(0.15)
                } else if pnl < 0 {
                    Color.semanticRed.opacity(0.15)
                } else {
                    Color.clear
                }
            } else if isToday {
                Color.accent.opacity(0.08)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Grid and bucketing (static so they can be unit-tested)

extension TradeCalendar {
    /// Calendar the month grid is laid out in: trading-day dates (New York), with the user's
    /// first weekday and language for the column order and headers
    static func gridCalendar(firstWeekday: Int = Calendar.current.firstWeekday, locale: Locale = .current) -> Calendar {
        var cal = TradingCalendar.calendar
        cal.firstWeekday = firstWeekday
        cal.locale = locale
        return cal
    }

    /// Net P&L per trading day, keyed by the day's New York midnight
    static func dailyPnL(for trades: [Trade]) -> [Date: Double] {
        TradingCalendar.dailyPnL(trades)
    }

    /// Every day of the month containing `month`
    static func days(inMonthOf month: Date, calendar: Calendar) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let components = calendar.dateComponents([.year, .month], from: month)
        return range.compactMap { day in
            calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))
        }
    }

    /// Empty cells before the 1st so it sits under its weekday header
    static func leadingBlankCount(for days: [Date], calendar: Calendar) -> Int {
        guard let firstDay = days.first else { return 0 }
        return (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
    }

    /// Column headers, left to right, starting at the calendar's first weekday
    /// (`shortWeekdaySymbols` always starts on Sunday)
    static func weekdayHeaders(calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        let start = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[start...] + symbols[..<start])
    }

    /// "October 2026", for the month as seen in New York
    static func monthTitle(_ month: Date, locale: Locale = .autoupdatingCurrent) -> String {
        var style = TradingCalendar.formatStyle.month(.wide).year()
        style.locale = locale
        return month.formatted(style)
    }

    /// Whether `date` is today's trading day (the New York date of `now`)
    static func isToday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        TradingCalendar.isSameDay(date, now)
    }
}
