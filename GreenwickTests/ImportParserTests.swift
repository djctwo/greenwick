import XCTest
@testable import Greenwick

/// CSV import: detection and parsing of every bundled sample, plus headline stats checked
/// against values computed independently from the sample files.
final class ImportParserTests: XCTestCase {

    /// Folder with the fictional sample exports (`TestData/` at the repo root)
    static let testDataDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TestData", isDirectory: true)

    func samplePath(_ name: String) -> String {
        Self.testDataDir.appendingPathComponent(name).path
    }

    func parseSample(_ name: String) throws -> (GenericCSVParser.Platform, [Trade]) {
        let detection = try GenericCSVParser.detect(fileAt: samplePath(name))
        let mapping = try XCTUnwrap(detection.mapping, "\(name) should auto-detect")
        return (detection.platform, try GenericCSVParser.parse(fileAt: samplePath(name), mapping: mapping))
    }

    // MARK: - Every sample

    func testEverySampleDetectsAndParses() throws {
        let expected: [(String, GenericCSVParser.Platform, Int)] = [
            ("thinkorswim_sample.csv", .thinkorswim, 10),
            ("interactive_brokers_sample.csv", .interactiveBrokers, 10),
            ("webull_sample.csv", .webull, 8),
            ("tradingview_sample.csv", .tradingView, 7),
            ("ninjatrader_sample.csv", .ninjaTrader, 8),
            ("robinhood_sample.csv", .robinhood, 6),
            ("schwab_sample.csv", .schwab, 6),
            ("fidelity_sample.csv", .fidelity, 5),
            ("etrade_sample.csv", .etrade, 5),
            ("tastytrade_sample.csv", .tastytrade, 5),
        ]
        for (file, platform, count) in expected {
            let (detected, trades) = try parseSample(file)
            XCTAssertEqual(detected, platform, file)
            XCTAssertEqual(trades.count, count, "\(file) trade count")
            XCTAssertEqual(Set(trades.map(\.ticket)).count, trades.count, "\(file) tickets must be unique")
        }
    }

    func testGenericSampleFallsBackToManualMapping() throws {
        let detection = try GenericCSVParser.detect(fileAt: samplePath("generic_sample.csv"))
        XCTAssertEqual(detection.platform, .generic)
        XCTAssertNil(detection.mapping)
    }

    // MARK: - Headline stats (expected values computed separately from the CSVs)
    // P&L is net of commissions and fees (profit column minus the commission column).

    func testNinjaTraderHeadlineStats() throws {
        let (_, trades) = try parseSample("ninjatrader_sample.csv")
        let m = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(m.totalTrades, 8)
        XCTAssertEqual(m.totalProfit, 1814.06, accuracy: 0.001)
        XCTAssertEqual(m.winRate, 87.5, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 8.429192, accuracy: 0.0001)
        XCTAssertEqual(m.expectancy, 226.7575, accuracy: 0.001)
        XCTAssertEqual(m.totalCommissions, 33.44, accuracy: 0.001)
    }

    func testThinkorswimHeadlineStats() throws {
        let (_, trades) = try parseSample("thinkorswim_sample.csv")
        let m = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(m.totalProfit, 2608.3, accuracy: 0.001)
        XCTAssertEqual(m.winRate, 70.0, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 3.802815, accuracy: 0.0001)
        XCTAssertEqual(m.expectancy, 260.83, accuracy: 0.001)
    }

    func testRobinhoodFIFOHeadlineStats() throws {
        let (_, trades) = try parseSample("robinhood_sample.csv")
        let m = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(m.totalProfit, 856.0, accuracy: 0.001)
        XCTAssertEqual(m.winRate, 66.6667, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 2.35873, accuracy: 0.0001)
        XCTAssertEqual(m.expectancy, 142.666667, accuracy: 0.001)
    }

    func testSchwabFIFOHeadlineStats() throws {
        let (_, trades) = try parseSample("schwab_sample.csv")
        let m = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(m.totalProfit, 1012.98, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 3.411283, accuracy: 0.0001)
        XCTAssertEqual(m.totalCommissions, 0.52, accuracy: 0.0001)
    }

    // MARK: - Re-import and IDs

    func testReimportGivesSameTickets() throws {
        let (_, first) = try parseSample("thinkorswim_sample.csv")
        let (_, second) = try parseSample("thinkorswim_sample.csv")
        XCTAssertEqual(first.map(\.ticket), second.map(\.ticket))
        let (_, fifoFirst) = try parseSample("robinhood_sample.csv")
        let (_, fifoSecond) = try parseSample("robinhood_sample.csv")
        XCTAssertEqual(Set(fifoFirst.map(\.ticket)), Set(fifoSecond.map(\.ticket)))
    }

    func testReimportLaterGivesSameTickets() throws {
        // Files without broker IDs used to get clock-based IDs, so a later re-import duplicated them
        let (_, first) = try parseSample("webull_sample.csv")
        Thread.sleep(forTimeInterval: 1.2)
        let (_, later) = try parseSample("thinkorswim_sample.csv")
        let (_, firstAgain) = try parseSample("webull_sample.csv")
        XCTAssertEqual(first.map(\.ticket), firstAgain.map(\.ticket))
        let (_, tosFirst) = try parseSample("thinkorswim_sample.csv")
        XCTAssertEqual(later.map(\.ticket), tosFirst.map(\.ticket))
    }

    func testDifferentFilesWithSameTradeNumbersDoNotCollide() throws {
        // Two NinjaTrader exports both start at "Trade # 1"
        let header = "Trade #,Instrument,Market Position,Quantity,Entry Time,Exit Time,Entry Price,Exit Price,Profit"
        let a = try writeTemp(header + "\n1,AAPL,Long,10,03/24/2026 09:35:00,03/24/2026 10:15:00,100,101,10")
        let b = try writeTemp(header + "\n1,MSFT,Long,10,03/25/2026 09:35:00,03/25/2026 10:15:00,200,201,10")
        let ta = try parse(a), tb = try parse(b)
        XCTAssertNotEqual(ta.first?.ticket, tb.first?.ticket)
    }

    func testIdenticalRowsInOneFileAreKept() throws {
        let header = "Exec Time,Symbol,Side,Qty,Price,Net Price,P/L,Commission"
        let row = "03/24/26 09:31:15,AAPL,BUY,100,171.25,171.30,25.00,0.65"
        let trades = try parse(try writeTemp([header, row, row].joined(separator: "\n")))
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(Set(trades.map(\.ticket)).count, 2)
    }

    // MARK: - FIFO details

    func testFIFOShortSaleIsLabelledSell() throws {
        let header = "Activity Date,Process Date,Settle Date,Account Type,Instrument,Description,Trans Code,Quantity,Price,Amount,Suppressed"
        let csv = [header,
                   "3/24/2026,3/24/2026,3/26/2026,Brokerage,XYZ,Example,Sell,10,$50.00,$500.00,",
                   "3/25/2026,3/25/2026,3/27/2026,Brokerage,XYZ,Example,Buy,10,$45.00,($450.00),"].joined(separator: "\n")
        let trades = try parse(try writeTemp(csv))
        let trade = try XCTUnwrap(trades.first)
        XCTAssertEqual(trade.direction, .sell)
        XCTAssertEqual(trade.netProfit, 50)
        XCTAssertLessThan(trade.openTime, trade.closeTime)
    }

    func testTitleLineAboveRobinhoodHeaderIsSkipped() throws {
        let original = try String(contentsOfFile: samplePath("robinhood_sample.csv"), encoding: .utf8)
        let trades = try parse(try writeTemp("Account activity export\n" + original))
        XCTAssertEqual(trades.count, 6)
    }

    func testPartialFillCostsAllocatedPerSide() throws {
        let header = "Date,Action,Symbol,Description,Quantity,Price,Fees & Comm,Amount"
        let csv = ["\"Transactions for account Example\"", header,
                   "03/24/2026,Buy,XYZ,Example,100,$10.00,$1.00,-$1000",
                   "03/24/2026,Sell,XYZ,Example,50,$11.00,$0.50,$550",
                   "03/25/2026,Sell,XYZ,Example,50,$12.00,$0.50,$600",
                   "Transactions Total,,,,,,,$150"].joined(separator: "\n")
        let trades = try parse(try writeTemp(csv))
        XCTAssertEqual(trades.count, 2)
        let totalCommission = trades.reduce(Decimal(0)) { $0 + $1.commission }
        XCTAssertEqual(NSDecimalNumber(decimal: totalCommission).doubleValue, 2.0, accuracy: 0.0001)
    }

    func testOneSellAgainstTwoBuysCountsSellFeesOnce() throws {
        let header = "Date,Action,Symbol,Description,Quantity,Price,Fees & Comm,Amount"
        let csv = ["\"Transactions for account Example\"", header,
                   "03/24/2026,Buy,XYZ,Example,50,$10.00,,-$500",
                   "03/24/2026,Buy,XYZ,Example,50,$10.00,,-$500",
                   "03/25/2026,Sell,XYZ,Example,100,$11.00,$1.00,$1099",
                   "Transactions Total,,,,,,,$99"].joined(separator: "\n")
        let trades = try parse(try writeTemp(csv))
        XCTAssertEqual(trades.count, 2)
        let fees = trades.reduce(Decimal(0)) { $0 + $1.commission }
        let net = trades.reduce(Decimal(0)) { $0 + $1.netProfit }
        XCTAssertEqual(NSDecimalNumber(decimal: fees).doubleValue, 1.0, accuracy: 0.0001)
        XCTAssertEqual(NSDecimalNumber(decimal: net).doubleValue, 99.0, accuracy: 0.0001)
    }

    func testImportedProfitIsNetOfCommission() throws {
        let header = "Exec Time,Symbol,Side,Qty,Price,Net Price,P/L,Commission"
        let trades = try parse(try writeTemp(header + "\n03/24/26 09:31:15,AAPL,BUY,100,171.25,171.30,25.00,-1.50"))
        XCTAssertEqual(trades.first?.netProfit, Decimal(string: "23.5"))
        XCTAssertEqual(trades.first?.commission, Decimal(string: "1.5"))
    }

    // MARK: - Helpers

    func parse(_ path: String) throws -> [Trade] {
        let detection = try GenericCSVParser.detect(fileAt: path)
        let mapping = try XCTUnwrap(detection.mapping)
        return try GenericCSVParser.parse(fileAt: path, mapping: mapping)
    }

    func writeTemp(_ content: String, ext: String = "csv") throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("greenwick-test-\(UUID().uuidString).\(ext)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }
}
