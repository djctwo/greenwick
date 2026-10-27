import Foundation

/// Exchange-time helpers on `Date`. All of them go through `TradingCalendar`, so the
/// exchange's time zone and session hours are defined once (`Market.default`, US/New York).
extension Date {
    /// Calendar configured for UTC
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return cal
    }()

    /// UTC hour component
    var utcHour: Int {
        Self.utcCalendar.component(.hour, from: self)
    }

    /// Eastern Time (exchange) hour component
    var etHour: Int {
        TradingCalendar.hour(self)
    }

    /// Eastern Time (exchange) minute component
    var etMinute: Int {
        TradingCalendar.minute(self)
    }

    /// Whether this date falls on a weekend (Saturday or Sunday) in ET
    var isWeekend: Bool {
        TradingCalendar.isWeekend(self)
    }

    /// Market session based on Eastern Time; weekends are `.extended`
    var marketSession: MarketSession {
        TradingCalendar.session(self)
    }

    /// All currently active market sessions (by time of day only)
    var activeMarketSessions: [MarketSession] {
        [TradingCalendar.sessionIgnoringWeekend(self)]
    }

    /// Short day-of-week string (Mon, Tue, etc.) in ET. Always English: it is stored with
    /// each trade and used as a key.
    var shortDayName: String {
        TradingCalendar.weekdayName(self)
    }

    /// Format for display in trade table — always in ET for consistency with the P&L calendar
    var tradeDisplayString: String {
        TradingCalendar.formatter("MMM d, HH:mm").string(from: self)
    }

    /// Time until next session boundary (in ET)
    var timeToNextSession: TimeInterval {
        TradingCalendar.timeToNextSession(from: self)
    }
}
