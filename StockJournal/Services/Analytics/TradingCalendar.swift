import Foundation

/// An exchange: its time zone and session hours. The one place those are defined.
///
/// Greenwick supports US stocks today, so `Market.default` is `.us` and nothing else is
/// used. Supporting another exchange later (London, Frankfurt, Tokyo…) means adding a value
/// here and choosing it as the default (or per trade); every day bucket, weekday, ET hour and
/// session label follows from it.
struct Market: Sendable, Equatable {
    /// Short name, e.g. "US"
    let name: String
    /// Time zone the exchange's trading day and session hours are defined in
    let timeZone: TimeZone
    /// Session boundaries in minutes after local midnight
    let preMarketOpen: Int
    let regularOpen: Int
    let regularClose: Int
    let afterHoursClose: Int

    /// US equities (NYSE/Nasdaq), New York time: pre-market 04:00, regular 09:30–16:00,
    /// after-hours to 20:00
    static let us = Market(
        name: "US",
        timeZone: TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600) ?? .gmt,
        preMarketOpen: 4 * 60,
        regularOpen: 9 * 60 + 30,
        regularClose: 16 * 60,
        afterHoursClose: 20 * 60
    )

    /// The market every statistic is bucketed in
    static let `default` = Market.us

    /// Session for a time of day given as minutes after local midnight (weekends are
    /// handled by the caller)
    func session(atMinute minute: Int) -> MarketSession {
        if minute >= preMarketOpen && minute < regularOpen { return .preMarket }
        if minute >= regularOpen && minute < regularClose { return .regular }
        if minute >= regularClose && minute < afterHoursClose { return .afterHours }
        return .extended
    }

    /// Next session boundary after `minute` (may be past midnight: next day's pre-market)
    func nextBoundary(afterMinute minute: Int) -> Int {
        [preMarketOpen, regularOpen, regularClose, afterHoursClose].first { minute < $0 }
            ?? 24 * 60 + preMarketOpen
    }
}

/// The trading calendar of `Market.default` (US: Gregorian, America/New_York).
///
/// A stock trade belongs to its exchange trading day, not to the day on the user's clock.
/// A trade closed Friday 18:50 ET is a Friday trade for a user in Berlin (00:50 Saturday)
/// or Tokyo (07:50 Saturday) too. Pre-market and after-hours stay on their exchange date.
///
/// Every per-day, per-weekday, per-week and per-month statistic, every "today", and every
/// ET hour or minute in the app goes through this type, so they all agree. Daylight saving
/// follows the exchange's own rules (US: second Sunday of March, first Sunday of November):
/// the time zone handles it, which is why nothing here adds or subtracts a fixed offset.
enum TradingCalendar {

    // MARK: - Calendar

    /// The exchange whose calendar this is
    static let market = Market.default

    /// The exchange's time zone (New York for the US market)
    static let timeZone: TimeZone = market.timeZone

    /// Gregorian in the exchange's time zone. POSIX locale so weekday names are always
    /// "Mon"…"Sun"; trading weeks start on Monday.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    /// Weekday names indexed by `Calendar` weekday - 1 (Sunday first)
    static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The five trading weekdays, Monday first (chart order)
    static let tradingWeekdays = ["Mon", "Tue", "Wed", "Thu", "Fri"]

    // MARK: - Days

    /// Start (exchange midnight: New York for the US) of the trading day `date` falls on
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// "2026-10-23": the exchange date of `date`, for use as a dictionary key
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Exchange midnight of a `dayKey`
    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Whether two moments fall on the same exchange date
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    // MARK: - Weeks and months

    /// Monday 00:00 ET of the trading week containing `date`
    static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(date)
    }

    /// The 1st of the month (00:00 ET) containing `date`
    static func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? startOfDay(date)
    }

    /// "2026-07": the exchange year and month of `date`
    static func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: - Weekday, hour, minute

    /// 1 = Sunday … 7 = Saturday, in exchange time
    static func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// "Mon" … "Sun" (never localised: these are also stored and used as keys)
    static func weekdayName(_ date: Date) -> String {
        weekdayNames[(weekday(date) - 1 + 7) % 7]
    }

    /// Saturday or Sunday in exchange time
    static func isWeekend(_ date: Date) -> Bool {
        let day = weekday(date)
        return day == 1 || day == 7
    }

    /// Hour of the day in exchange time (0–23)
    static func hour(_ date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    /// Minute of the hour in exchange time
    static func minute(_ date: Date) -> Int {
        calendar.component(.minute, from: date)
    }

    /// Minutes after exchange midnight
    static func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: - Sessions

    /// Session of `date` in the exchange's hours; weekends are `.extended`
    static func session(_ date: Date) -> MarketSession {
        isWeekend(date) ? .extended : market.session(atMinute: minuteOfDay(date))
    }

    /// Session at this time of day, ignoring the weekday (the sidebar's live clock)
    static func sessionIgnoringWeekend(_ date: Date) -> MarketSession {
        market.session(atMinute: minuteOfDay(date))
    }

    /// Seconds from `date` to the next session boundary
    static func timeToNextSession(from date: Date) -> TimeInterval {
        let minute = minuteOfDay(date)
        return TimeInterval((market.nextBoundary(afterMinute: minute) - minute) * 60)
    }

    // MARK: - Display

    /// A date format in exchange time, in the user's language: `formatStyle.month().day()`
    static var formatStyle: Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone)
    }

    /// `DateFormatter` in exchange time with a fixed pattern (user's language)
    static func formatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter
    }
}

// MARK: - Bucketing trades

extension TradingCalendar {
    /// Net P&L per trading day, keyed by the day's exchange midnight
    static func dailyPnL(_ trades: [Trade]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for trade in trades {
            result[trade.tradingDay, default: 0] += trade.profitDouble
        }
        return result
    }

    /// Number of distinct trading days with at least one closed trade
    static func tradingDayCount(_ trades: [Trade]) -> Int {
        Set(trades.map(\.tradingDay)).count
    }

    /// Net P&L of trades closed on the trading day that `now` falls on (the daily loss limit's "today")
    static func pnl(onTradingDayOf now: Date, _ trades: [Trade]) -> Double {
        let today = startOfDay(now)
        return trades
            .filter { $0.tradingDay == today }
            .reduce(0) { $0 + $1.profitDouble }
    }

    /// Trades grouped by the weekday ("Mon"…) of their trading day
    static func groupedByWeekday(_ trades: [Trade]) -> [String: [Trade]] {
        Dictionary(grouping: trades) { $0.tradingWeekday }
    }
}

// MARK: - Trade

extension Trade {
    /// The trading day this trade counts toward: exchange midnight (New York) of its close.
    /// Used by the P&L calendar, daily stats, "today", trading-day counts and exports.
    var tradingDay: Date { TradingCalendar.startOfDay(closeTime) }

    /// Weekday ("Mon"…"Fri") of `tradingDay`. Every P&L-by-weekday statistic uses this,
    /// so it always matches the P&L calendar.
    var tradingWeekday: String { TradingCalendar.weekdayName(closeTime) }

    /// Weekday of the entry in exchange time. Pairs with `hour` (the entry hour, ET) in the
    /// weekday × hour heatmaps, which show when trades are taken.
    var entryWeekday: String { TradingCalendar.weekdayName(openTime) }
}
