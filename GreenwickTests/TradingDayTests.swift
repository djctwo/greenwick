import XCTest
@testable import Greenwick

/// Stock trades belong to their US exchange trading day: the calendar date of the close in
/// New York (America/New_York), pre-market and after-hours included. That must not depend on
/// the time zone of the Mac. A Friday 18:50 ET after-hours close is 00:50 Saturday in Berlin
/// and 07:50 Saturday in Tokyo, and it is still a Friday trade.
///
/// Every test runs once per zone below, with the process's default time zone switched to that
/// zone (what `Calendar.current` and `DateFormatter` follow), then restored.
@MainActor
final class TradingDayTests: XCTestCase {

    static let zones = ["Europe/Berlin", "Asia/Tokyo", "America/Los_Angeles"]

    override class func setUp() {
        super.setUp()
        // Shows in the test log which zone the whole process runs in (TZ / TEST_RUNNER_TZ)
        print("TradingDayTests: process time zone \(TimeZone.current.identifier)")
    }

    // MARK: - Helpers (independent of the app's own calendar code)

    static let newYork = TimeZone(identifier: "America/New_York")!

    /// A moment written as New York wall-clock time
    static func et(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = newYork
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Runs `body` once per zone with the default time zone set to it
    func inEachZone(_ zones: [String] = TradingDayTests.zones, _ body: (String) throws -> Void) rethrows {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        for zone in zones {
            NSTimeZone.default = TimeZone(identifier: zone)!
            XCTAssertEqual(Calendar.current.timeZone.identifier, zone, "time zone override did not take")
            try body(zone)
        }
    }

    /// A trade built the way the importers build one (weekday and hour taken from the open, in ET)
    static func trade(
        open: Date, close: Date, profit: Decimal, symbol: String = "AAPL", dayOfWeek: String? = nil
    ) -> Trade {
        Trade(
            id: nil, ticket: Int64.random(in: 1...Int64.max), symbol: symbol, direction: .buy, shares: 100,
            openTime: open, closeTime: close, durationMin: Int(close.timeIntervalSince(open) / 60),
            openPrice: 100, closePrice: 101, sl: 0, tp: 0, netProfit: profit,
            maePoints: 0, mfePoints: 0, rMultiple: 0, session: open.marketSession,
            dayOfWeek: dayOfWeek ?? open.shortDayName, hour: open.etHour,
            rangeSize: 0, hitBreakeven: false, scaledIn: false, comment: "",
            timeToMFEMin: 0, slDistPoints: 0, slippagePoints: 0, importedAt: Date()
        )
    }

    /// Imports a NinjaTrader export (times in the file are New York time, as brokers write them)
    func importNinjaTrader(_ rows: [String]) throws -> [Trade] {
        let csv = (["Trade #,Instrument,Market Position,Quantity,Entry Time,Exit Time,Entry Price,Exit Price,Profit,MAE,MFE,Commission"] + rows)
            .joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trading-day-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let detection = try GenericCSVParser.detect(fileAt: url.path)
        let mapping = try XCTUnwrap(detection.mapping)
        return try GenericCSVParser.parse(fileAt: url.path, mapping: mapping)
    }

    /// The P&L calendar cell for day-of-month `day` (nil = empty cell), plus the header above it
    func calendarCell(day: Int, ofMonthContaining month: Date, trades: [Trade], firstWeekday: Int = 1)
        -> (pnl: Double?, header: String) {
        let grid = TradeCalendar.gridCalendar(firstWeekday: firstWeekday, locale: Locale(identifier: "en_US_POSIX"))
        let days = TradeCalendar.days(inMonthOf: month, calendar: grid)
        let pnl = TradeCalendar.dailyPnL(for: trades)
        let index = day - 1
        let column = (TradeCalendar.leadingBlankCount(for: days, calendar: grid) + index) % 7
        return (pnl[grid.startOfDay(for: days[index])], TradeCalendar.weekdayHeaders(calendar: grid)[column])
    }

    // MARK: - The reported bug: Friday after-hours shown on Saturday

    func testFridayAfterHoursTradeIsOnFridayInPnLCalendar() throws {
        // Fri 23 Oct 2026: one regular-hours trade and one after-hours trade closed 18:50 ET
        let trades = try importNinjaTrader([
            "1,AAPL,Long,100,10/23/2026 10:00:00,10/23/2026 10:30:00,171.00,171.50,50.00,0.10,0.60,0.00",
            "2,TSLA,Long,100,10/23/2026 18:20:00,10/23/2026 18:50:00,180.00,181.25,125.00,0.10,1.50,0.00",
        ])
        XCTAssertEqual(trades.count, 2)
        try inEachZone { zone in
            for firstWeekday in [1, 2] { // Sunday-first (US) and Monday-first (Germany) grids
                let friday = calendarCell(day: 23, ofMonthContaining: trades[0].closeTime, trades: trades, firstWeekday: firstWeekday)
                XCTAssertEqual(try XCTUnwrap(friday.pnl, "\(zone): Friday 23 Oct is empty"), 175, accuracy: 0.001, zone)
                XCTAssertEqual(friday.header, "Fri", "\(zone), firstWeekday \(firstWeekday): column header above the 23rd")
                let saturday = calendarCell(day: 24, ofMonthContaining: trades[0].closeTime, trades: trades, firstWeekday: firstWeekday)
                XCTAssertNil(saturday.pnl, "\(zone): the after-hours trade leaked into Saturday 24 Oct")
            }
            let october = TradeCalendar.days(inMonthOf: trades[0].closeTime, calendar: TradeCalendar.gridCalendar())
            XCTAssertEqual(TradeCalendar.monthTitle(october[0], locale: Locale(identifier: "en_US_POSIX")), "October 2026", zone)
        }
    }

    func testFridayAfterHoursTradeCountsAsFridayInWeekdayStats() throws {
        let trades = try importNinjaTrader([
            "1,TSLA,Long,100,10/23/2026 18:20:00,10/23/2026 18:50:00,180.00,181.25,125.00,0.10,1.50,0.00",
        ])
        inEachZone { zone in
            let chart = DayOfWeekChart.data(for: trades)
            XCTAssertEqual(chart.map(\.day), ["Fri"], zone)
            XCTAssertEqual(chart.first?.profit ?? 0, 125, accuracy: 0.001, zone)
            XCTAssertEqual(MetricsCalculator.edgeByDay(from: trades).map(\.label), ["Fri"], zone)
            let dayConditions = MetricsCalculator.allEdgeConditions(from: trades, tradingDays: 1)
                .filter { $0.dimension == "Day" }
            XCTAssertEqual(dayConditions.map(\.label), ["Fri"], zone)
        }
    }

    /// A trade stored with a localised weekday label (an import made on a Mac set to German
    /// writes "Fr.") must still show up in the Friday bar.
    func testWeekdayStatsDoNotDependOnTheStoredLabelsLanguage() {
        let trade = Self.trade(open: Self.et(2026, 10, 23, 18, 20), close: Self.et(2026, 10, 23, 18, 50),
                               profit: 125, dayOfWeek: "Fr.")
        inEachZone { zone in
            XCTAssertEqual(DayOfWeekChart.data(for: [trade]).map(\.day), ["Fri"], zone)
            XCTAssertEqual(MetricsCalculator.edgeByDay(from: [trade]).map(\.label), ["Fri"], zone)
        }
    }

    /// Weekday statistics follow the trading day of the close, like the calendar, so a swing
    /// trade bought Thursday and sold Friday is a Friday result in both.
    func testWeekdayStatsUseTheCloseTradingDayLikeTheCalendar() {
        let swing = Self.trade(open: Self.et(2026, 10, 22, 15, 30), close: Self.et(2026, 10, 23, 18, 50), profit: 80)
        inEachZone { zone in
            XCTAssertEqual(DayOfWeekChart.data(for: [swing]).map(\.day), ["Fri"], zone)
            let friday = calendarCell(day: 23, ofMonthContaining: swing.closeTime, trades: [swing])
            XCTAssertEqual(friday.pnl ?? 0, 80, accuracy: 0.001, zone)
        }
    }

    func testFridayEveningTradeIsNotFlaggedAsWeekend() {
        let friday = Self.trade(open: Self.et(2026, 10, 23, 18, 20), close: Self.et(2026, 10, 23, 18, 50), profit: 125)
        let saturday = Self.trade(open: Self.et(2026, 10, 24, 11, 0), close: Self.et(2026, 10, 24, 11, 30), profit: 10)
        inEachZone { zone in
            XCTAssertEqual(DataQuality.weekendTradeCount([friday]), 0, zone)
            XCTAssertEqual(DataQuality.weekendTradeCount([friday, saturday]), 1, zone)
        }
    }

    // MARK: - Daily stats, "today" and trading-day counts

    func testTradingDayCountAndDailyLossLimitUseTheNewYorkDay() {
        let morning = Self.trade(open: Self.et(2026, 10, 23, 9, 45), close: Self.et(2026, 10, 23, 10, 0), profit: 50)
        let evening = Self.trade(open: Self.et(2026, 10, 23, 18, 20), close: Self.et(2026, 10, 23, 18, 50), profit: -200)
        let trades = [morning, evening]
        inEachZone { zone in
            XCTAssertEqual(PropFirmTracker.tradingDayCount(trades), 1, "\(zone): one trading day")
            // 19:30 ET Friday is already Saturday in Berlin and Tokyo; the trading day is still Friday
            XCTAssertEqual(PropFirmTracker.todayPnL(trades, now: Self.et(2026, 10, 23, 19, 30)), -150, accuracy: 0.001, zone)
            XCTAssertEqual(PropFirmTracker.todayPnL(trades, now: Self.et(2026, 10, 24, 10, 0)), 0, accuracy: 0.001,
                           "\(zone): nothing traded on Saturday")
        }
    }

    func testMonthEndAfterHoursTradeStaysInItsMonth() {
        // Fri 31 Jul 2026 18:50 ET = Sat 1 Aug 00:50 in Berlin
        let trade = Self.trade(open: Self.et(2026, 7, 31, 18, 20), close: Self.et(2026, 7, 31, 18, 50), profit: 125)
        inEachZone { zone in
            XCTAssertEqual(MonthlyReturns.monthlyData(for: [trade]).map(\.id), ["2026-07"], zone)
        }
    }

    func testJournalDateFiltersStartAtNewYorkMidnight() {
        let fridayEvening = Self.et(2026, 10, 23, 19, 30)
        inEachZone { zone in
            XCTAssertEqual(JournalViewModel.cutoff(for: .today, now: fridayEvening), Self.et(2026, 10, 23, 0, 0), zone)
            XCTAssertEqual(JournalViewModel.cutoff(for: .thisWeek, now: fridayEvening), Self.et(2026, 10, 19, 0, 0),
                           "\(zone): trading weeks start Monday")
            XCTAssertEqual(JournalViewModel.cutoff(for: .thisMonth, now: Self.et(2026, 7, 31, 18, 30)), Self.et(2026, 7, 1, 0, 0), zone)
        }
    }

    // MARK: - Daylight saving time (US and Europe switch on different dates)

    func testAfterHoursTradesAroundDaylightSavingChanges() {
        let cases: [(String, Date, Int)] = [
            // US already on EDT, Europe still on CET (9-28 Mar 2026): offset Berlin-NY is 5 h
            ("Fri 13 Mar 2026 19:30 EDT", Self.et(2026, 3, 13, 19, 30), 13),
            // Europe back on CET, US still on EDT (25 Oct-1 Nov 2026)
            ("Fri 30 Oct 2026 19:30 EDT", Self.et(2026, 10, 30, 19, 30), 30),
            // Both on standard time
            ("Fri 6 Nov 2026 18:50 EST", Self.et(2026, 11, 6, 18, 50), 6),
            // Overnight session just after New York midnight: still Monday evening in Los Angeles
            ("Tue 10 Mar 2026 01:30 EDT", Self.et(2026, 3, 10, 1, 30), 10),
        ]
        inEachZone { zone in
            for (label, close, day) in cases {
                let trade = Self.trade(open: close.addingTimeInterval(-600), close: close, profit: 42)
                let cell = calendarCell(day: day, ofMonthContaining: close, trades: [trade])
                XCTAssertEqual(cell.pnl ?? 0, 42, accuracy: 0.001, "\(zone): \(label) not on day \(day)")
                XCTAssertNil(calendarCell(day: day + 1, ofMonthContaining: close, trades: [trade]).pnl, "\(zone): \(label)")
            }
        }
    }

    func testCalendarGridFollowsNewYorkDaylightSaving() {
        inEachZone { zone in
            let grid = TradeCalendar.gridCalendar()
            let march = TradeCalendar.days(inMonthOf: Self.et(2026, 3, 15, 12, 0), calendar: grid)
            let november = TradeCalendar.days(inMonthOf: Self.et(2026, 11, 15, 12, 0), calendar: grid)
            XCTAssertEqual(march.count, 31, zone)
            XCTAssertEqual(november.count, 30, zone)
            XCTAssertEqual(march[0], Self.et(2026, 3, 1, 0, 0), "\(zone): grid days are New York midnights")
            // Sun 8 Mar 2026 has 23 hours in New York, Sun 1 Nov 2026 has 25
            XCTAssertEqual(march[8].timeIntervalSince(march[7]), 23 * 3600, zone)
            XCTAssertEqual(november[1].timeIntervalSince(november[0]), 25 * 3600, zone)
        }
    }

    // MARK: - Session hours and stored labels (one `Market`, unchanged US behaviour)

    func testSessionsAndEntryLabelsAreNewYorkTimeInEveryZone() throws {
        let sessions: [(Int, Int, MarketSession)] = [
            (3, 59, .extended), (4, 0, .preMarket), (9, 29, .preMarket), (9, 30, .regular),
            (15, 59, .regular), (16, 0, .afterHours), (19, 59, .afterHours), (20, 0, .extended),
        ]
        let trades = try importNinjaTrader([
            "1,TSLA,Long,100,10/23/2026 18:20:00,10/23/2026 18:50:00,180.00,181.25,125.00,0.10,1.50,0.00",
        ])
        inEachZone { zone in
            for (hour, minute, expected) in sessions {
                XCTAssertEqual(Self.et(2026, 10, 23, hour, minute).marketSession, expected, "\(zone) \(hour):\(minute)")
            }
            XCTAssertEqual(Self.et(2026, 10, 24, 11, 0).marketSession, .extended, "\(zone): Saturday")
            XCTAssertEqual(Self.et(2026, 10, 23, 9, 0).timeToNextSession, 30 * 60, zone)
            XCTAssertEqual(Self.et(2026, 10, 23, 20, 30).timeToNextSession, (7 * 60 + 30) * 60, zone)
            // What the importer stores: English weekday and New York hour of the entry
            XCTAssertEqual(trades.first?.dayOfWeek, "Fri", zone)
            XCTAssertEqual(trades.first?.hour, 18, zone)
            XCTAssertEqual(trades.first?.session, .afterHours, zone)
            XCTAssertEqual(trades.first?.tradingWeekday, "Fri", zone)
        }
        XCTAssertEqual(Market.default, .us)
        XCTAssertEqual(MarketSession.allCases.map(\.startHourET), [4, 9, 16, 4])
        XCTAssertEqual(MarketSession.allCases.map(\.endHourET), [9, 16, 20, 20])
    }

    // MARK: - Sample data unchanged

    func testSampleDataHeadlineNumbersAreTheSameInEveryZone() {
        inEachZone { zone in
            let trades = DemoDataGenerator.generateTrades()
            let m = MetricsCalculator.calculate(from: trades)
            XCTAssertEqual(m.totalTrades, 30, zone)
            XCTAssertEqual(m.totalProfit, 1975, accuracy: 0.001, zone)
            XCTAssertEqual(m.winRate, 66.6667, accuracy: 0.001, zone)
            let daily = TradeCalendar.dailyPnL(for: trades)
            XCTAssertEqual(daily.values.reduce(0, +), 1975, accuracy: 0.001, zone)
            XCTAssertEqual(DayOfWeekChart.data(for: trades).map(\.profit).reduce(0, +), 1975, accuracy: 0.001,
                           "\(zone): every sample trade is on a weekday")
            var ny = Calendar(identifier: .gregorian)
            ny.timeZone = Self.newYork
            for day in daily.keys {
                XCTAssertFalse(ny.isDateInWeekend(day), "\(zone): sample P&L on a weekend")
                XCTAssertEqual(ny.startOfDay(for: day), day, "\(zone): day keys are New York midnights")
            }
        }
    }
}
