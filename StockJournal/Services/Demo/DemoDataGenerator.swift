import Foundation

/// Generates realistic sample stock trades for first-launch demo
/// 30 trades across 8 tickers, mixed sessions, 60% win rate
enum DemoDataGenerator {
    /// Comment shown on every sample trade
    static let sampleComment = "Sample (fictional)"
    /// Sample tickets are ticketBase ..< ticketBase + 30 (fixed, so loading twice adds nothing)
    static let ticketBase: Int64 = 900_000
    static let sampleCount = 30

    /// Marks sample trades written by versions without the isSample column (comment "Demo")
    static let legacySampleMarkingSQL = """
        UPDATE trades SET isSample = 1
        WHERE comment IN ('Demo', 'Sample (fictional)') AND ticket BETWEEN 900000 AND 900029
        """

    static func generateTrades() -> [Trade] {
        let now = Date()
        // Demo trades are placed in US Eastern time on weekdays, like real US trading
        let calendar = TradingCalendar.calendar

        // Trade templates: (symbol, direction, shares, profit, rMultiple, session, hour, durationMin, maePoints, mfePoints, slDistPoints, sector, industry)
        let templates: [(String, TradeDirection, Double, Decimal, Double, MarketSession, Int, Int, Double, Double, Double, String, String)] = [
            // Week 1 — Tech focus, morning momentum
            ("AAPL",  .buy,  100, 185,   1.7, .regular,    10, 42, 1.20, 2.80, 1.65, "Technology", "Consumer Electronics"),
            ("TSLA",  .sell,  50, -95,  -0.9, .regular,    11, 28, 4.40, 2.00, 3.00, "Consumer Discretionary", "Auto Manufacturers"),
            ("NVDA",  .buy,   75, 320,   2.4, .regular,    10, 55, 1.60, 7.60, 2.80, "Technology", "Semiconductors"),
            ("MSFT",  .buy,  100, -120, -1.2, .preMarket,   7, 35, 2.50, 0.80, 1.40, "Technology", "Software"),
            ("AMD",   .buy,  150, 105,   1.0, .preMarket,   8, 20, 1.00, 1.80, 1.20, "Technology", "Semiconductors"),
            ("META",  .sell,  60, 195,   1.9, .regular,    13, 48, 2.50, 5.30, 3.00, "Technology", "Internet Content"),
            // Week 2 — Afternoon and after-hours
            ("GOOGL", .buy,   80, 155,   1.1, .regular,    14, 30, 1.40, 2.20, 1.50, "Technology", "Internet Content"),
            ("AAPL",  .sell, 100, -175, -1.5, .regular,    15, 40, 3.00, 1.20, 1.65, "Technology", "Consumer Electronics"),
            ("AMZN",  .sell,  50, 140,   1.4, .regular,    15, 25, 1.00, 4.80, 2.80, "Consumer Discretionary", "Internet Retail"),
            ("META",  .buy,   60, -100, -1.0, .regular,    10, 32, 3.20, 1.60, 3.00, "Technology", "Internet Content"),
            ("AMD",   .sell, 150, 120,   1.1, .afterHours, 17, 18, 0.80, 1.60, 1.20, "Technology", "Semiconductors"),
            ("TSLA",  .buy,   50, 350,   3.0, .regular,    11, 65, 1.20, 9.00, 3.00, "Consumer Discretionary", "Auto Manufacturers"),
            // Week 3 — Streak building
            ("GOOGL", .sell,  80, 165,   1.3, .regular,    13, 38, 1.20, 2.50, 1.50, "Technology", "Internet Content"),
            ("AAPL",  .buy,  100, 190,   1.8, .regular,    10, 50, 1.00, 3.00, 1.65, "Technology", "Consumer Electronics"),
            ("MSFT",  .buy,  100, 90,    0.9, .preMarket,   8, 22, 1.50, 2.00, 1.40, "Technology", "Software"),
            ("NVDA",  .sell,  75, -225, -1.7, .regular,    15, 55, 7.00, 1.60, 2.80, "Technology", "Semiconductors"),
            ("AMD",   .buy,  150, 90,    0.8, .preMarket,   5, 15, 0.80, 1.40, 1.20, "Technology", "Semiconductors"),
            ("AAPL",  .sell, 100, -80,  -0.8, .regular,    12, 28, 1.80, 1.00, 1.65, "Technology", "Consumer Electronics"),
            // Week 4 — Mixed, closing out month
            ("AMZN",  .buy,   50, 175,   1.5, .regular,    10, 45, 1.00, 5.60, 2.80, "Consumer Discretionary", "Internet Retail"),
            ("TSLA",  .buy,   50, 210,   2.2, .regular,     9, 58, 1.60, 7.00, 3.00, "Consumer Discretionary", "Auto Manufacturers"),
            ("MSFT",  .sell, 100, -110, -1.1, .afterHours, 18, 30, 2.20, 1.00, 1.40, "Technology", "Software"),
            ("META",  .buy,   60, 160,   1.6, .regular,    14, 42, 1.20, 4.50, 3.00, "Technology", "Internet Content"),
            ("AMD",   .sell, 150, -105, -1.0, .regular,    10, 25, 1.60, 0.80, 1.20, "Technology", "Semiconductors"),
            ("GOOGL", .sell,  80, 100,   1.0, .regular,    15, 35, 1.40, 2.00, 1.50, "Technology", "Internet Content"),
            ("NVDA",  .buy,   75, 280,   2.6, .regular,    11, 70, 1.00, 8.40, 2.80, "Technology", "Semiconductors"),
            ("MSFT",  .buy,  100, 120,   1.2, .preMarket,   8, 28, 1.00, 2.20, 1.40, "Technology", "Software"),
            ("META",  .sell,  60, -140, -1.4, .regular,    10, 38, 4.50, 1.60, 3.00, "Technology", "Internet Content"),
            ("AMD",   .buy,  150, 75,    0.7, .preMarket,   7, 12, 0.60, 1.20, 1.20, "Technology", "Semiconductors"),
            ("TSLA",  .buy,   50, -180, -1.8, .afterHours, 19, 45, 6.40, 1.60, 3.00, "Consumer Discretionary", "Auto Manufacturers"),
            ("AAPL",  .buy,  100, 80,    0.8, .regular,     9, 22, 1.20, 1.80, 1.65, "Technology", "Consumer Electronics"),
        ]

        let dayOfWeekNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]

        var trades: [Trade] = []

        for (index, t) in templates.enumerated() {
            // Spread trades across last 28 days, 1-2 per day
            let daysBack = 28 - (index * 28 / templates.count)
            var tradeDate = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
            // Move weekend dates back to the preceding Friday
            while calendar.isDateInWeekend(tradeDate) {
                tradeDate = calendar.date(byAdding: .day, value: -1, to: tradeDate) ?? tradeDate
            }

            // Set hour from template (ET market hours, 4-20 range)
            var components = calendar.dateComponents([.year, .month, .day], from: tradeDate)
            components.hour = t.6
            components.minute = Int.random(in: 5...55)
            let openTime = calendar.date(from: components)!
            let closeTime = calendar.date(byAdding: .minute, value: t.7, to: openTime)!

            let weekday = calendar.component(.weekday, from: openTime)
            // Map: 1=Sun->Fri, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat->Fri
            let dayIndex: Int
            if weekday == 1 || weekday == 7 {
                dayIndex = 4 // Map weekend to Fri
            } else {
                dayIndex = weekday - 2
            }
            let dayName = dayOfWeekNames[dayIndex]

            // Generate realistic stock prices based on ticker
            let openPrice: Decimal
            switch t.0 {
            case "AAPL":  openPrice = 185.50
            case "TSLA":  openPrice = 248.30
            case "NVDA":  openPrice = 875.20
            case "MSFT":  openPrice = 420.15
            case "AMD":   openPrice = 162.80
            case "META":  openPrice = 505.40
            case "GOOGL": openPrice = 175.60
            case "AMZN":  openPrice = 185.90
            default:      openPrice = 100.00
            }

            // Approximate close price from profit and shares
            let profitDouble = NSDecimalNumber(decimal: t.3).doubleValue
            let priceChange = profitDouble / t.2
            let closePrice: Decimal
            if t.1 == .buy {
                closePrice = openPrice + Decimal(priceChange)
            } else {
                closePrice = openPrice - Decimal(priceChange)
            }

            let trade = Trade(
                id: nil,
                ticket: ticketBase + Int64(index),
                symbol: t.0,
                direction: t.1,
                shares: t.2,
                openTime: openTime,
                closeTime: closeTime,
                durationMin: t.7,
                openPrice: openPrice,
                closePrice: closePrice,
                sl: t.1 == .buy ? openPrice - Decimal(t.10) : openPrice + Decimal(t.10),
                tp: t.1 == .buy ? openPrice + Decimal(t.9) * 2 : openPrice - Decimal(t.9) * 2,
                netProfit: t.3,
                maePoints: t.8,
                mfePoints: t.9,
                rMultiple: t.4,
                session: t.5,
                dayOfWeek: dayName,
                hour: t.6,
                rangeSize: Double.random(in: 2.0...8.0),
                hitBreakeven: t.3 > 0 && Bool.random(),
                scaledIn: false,
                comment: sampleComment,
                timeToMFEMin: Int(Double(t.7) * Double.random(in: 0.3...0.8)),
                slDistPoints: t.10,
                slippagePoints: Double.random(in: 0.01...0.10),
                sector: t.11,
                industry: t.12,
                volume: Int.random(in: 5_000_000...80_000_000),
                avgVolume: Int.random(in: 10_000_000...60_000_000),
                notes: "",
                tags: "",
                emotion: "",
                screenshots: "",
                checklistData: "",
                commission: Decimal(string: String(format: "%.2f", Double.random(in: 0.50...2.00)))!,
                swap: 0,
                importedAt: now,
                isSample: true
            )

            trades.append(trade)
        }

        return trades
    }
}
