import XCTest
@testable import Greenwick

/// Values that a crafted CSV or a crafted backup can put in the journal must never crash an
/// analytics screen, and the import must refuse values outside the documented limits.
final class HostileValueTests: XCTestCase {

    // MARK: - Helpers

    private func trade(_ i: Int, profit: Decimal, shares: Double = 100, durationMin: Int = 30) -> Trade {
        var t = DemoDataGenerator.generateTrades()[0]
        t.ticket = Int64(5_000_000 + i)
        t.netProfit = profit
        t.shares = shares
        t.durationMin = durationMin
        let open = Date(timeIntervalSince1970: 1_772_000_000 + Double(i) * 3_600)
        t.openTime = open
        t.closeTime = open.addingTimeInterval(1_800)
        return t
    }

    // MARK: - Double → Int conversions (F3, F4)

    func testSaturatingConversionNeverTraps() {
        XCTAssertEqual(Int(saturating: .nan), 0)
        XCTAssertEqual(Int(saturating: .infinity), .max)
        XCTAssertEqual(Int(saturating: -.infinity), .min)
        XCTAssertEqual(Int(saturating: 1e21), .max)
        XCTAssertEqual(Int(saturating: -1e21), .min)
        XCTAssertEqual(Int(saturating: 9_223_372_036_854_775_807.0), .max) // rounds up to 2^63
        XCTAssertEqual(Int(saturating: 42.9), 42)
        XCTAssertEqual(Int(saturating: -42.9), -42)
    }

    /// F3: winners with 1e9 shares, losers with 1e-12 shares → size after a loss / size
    /// after a win ≈ 1e21
    @MainActor
    func testCraftedShareSizesDoNotCrashTheRiskTab() {
        let trades = (0..<20).map { i in
            i.isMultiple(of: 2)
                ? trade(i, profit: 10, shares: 1e9)      // winner (follows a loss)
                : trade(i, profit: -10, shares: 1e-12)   // loser (follows a win)
        }
        let report = BehavioralAnalytics(trades: trades).report
        let score = try? XCTUnwrap(report?.disciplineScore)
        XCTAssertNotNil(score)
        XCTAssertTrue((0...100).contains(score ?? -1))
        for dimension in report?.dimensions ?? [] {
            XCTAssertTrue((0...100).contains(dimension.score), "\(dimension.name) = \(dimension.score)")
        }
    }

    /// F4: a P&L beyond Int range (FIFO pairing of 1e9 shares at $1e12) must not trap the chart
    @MainActor
    func testHugePnLDoesNotCrashTheDistributionChart() throws {
        let huge = try XCTUnwrap(Decimal(string: "-1000000000000000000000"))
        let buckets = WinLossDistribution(trades: [trade(0, profit: huge), trade(1, profit: 25)]).buckets
        XCTAssertFalse(buckets.isEmpty)
    }

    // MARK: - Integer sums (F6)

    func testDurationAveragesCannotOverflow() {
        let trades = [trade(0, profit: 10, durationMin: .max), trade(1, profit: -5, durationMin: .max),
                      trade(2, profit: 7, durationMin: .max)]
        let metrics = MetricsCalculator.calculate(from: trades)          // used to trap
        XCTAssertGreaterThan(metrics.averageDuration, 0)
        _ = PromptBuilder.edgeAnalysis(from: trades, metrics: metrics)   // used to trap
        XCTAssertEqual([Int.max, Int.max].overflowSafeAverage(), .max)
        XCTAssertEqual([10, 20, 31].overflowSafeAverage(), 20)
        XCTAssertEqual([Int]().overflowSafeAverage(), 0)
        XCTAssertEqual([Int.max, 1].saturatingSum(), .max)
        XCTAssertEqual([Int.min, -1].saturatingSum(), .min)
    }

    // MARK: - Import limits

    func testImportRejectsAbsurdlySmallShareCounts() {
        XCTAssertNil(GenericCSVParser.parseShares("0.000000000001"))
        XCTAssertNil(GenericCSVParser.parseShares("1e-12"))
        XCTAssertEqual(GenericCSVParser.parseShares("0.5"), 0.5)          // fractional shares stay
        XCTAssertEqual(GenericCSVParser.parseShares("0.000001"), 0.000001) // documented minimum
    }

    /// F4 root cause: FIFO pairing multiplied two bounded inputs into an unbounded P&L
    func testFIFOPairingRefusesPnLBeyondTheMaximum() {
        let day = Date(timeIntervalSince1970: 1_772_000_000)
        let txns = [
            GenericCSVParser.RawTransaction(symbol: "XYZ", isBuy: true, shares: 1_000_000_000,
                                            price: 1_000_000_000_000, date: day, commission: 0, fees: 0),
            GenericCSVParser.RawTransaction(symbol: "XYZ", isBuy: false, shares: 1_000_000_000,
                                            price: 0.01, date: day.addingTimeInterval(60), commission: 0, fees: 0),
            GenericCSVParser.RawTransaction(symbol: "ABC", isBuy: true, shares: 10,
                                            price: 100, date: day, commission: 1, fees: 0),
            GenericCSVParser.RawTransaction(symbol: "ABC", isBuy: false, shares: 10,
                                            price: 101, date: day.addingTimeInterval(60), commission: 1, fees: 0),
        ]
        let trades = GenericCSVParser.pairTransactions(txns, importedAt: day)
        XCTAssertEqual(trades.map(\.symbol), ["ABC"], "The pair with an out-of-range P&L must be skipped")
        for t in trades {
            XCTAssertLessThanOrEqual(abs(t.netProfit), GenericCSVParser.maxAbsAmount)
        }
    }

    /// Every write path stores only trades inside the limits (same rules as restore validation)
    func testRepositoryRefusesOutOfRangeTradesAndStripsControlCharacters() throws {
        let db = try DatabaseManager(inMemory: true)
        let repo = TradeRepository(database: db)
        var bad = trade(1, profit: 5)
        bad.durationMin = .max
        var tiny = trade(2, profit: 5, shares: 1e-12)
        tiny.ticket = 7_000_002
        var dirty = trade(3, profit: 5)
        dirty.symbol = "AA\rPL"
        dirty.notes = "line one\nline two\u{0007}"
        dirty.screenshots = "..,\(UUID().uuidString).jpg,../x.jpg"
        XCTAssertEqual(try repo.bulkInsert([bad, tiny, dirty]), 1)
        let stored = try XCTUnwrap(try repo.fetchAll().first)
        XCTAssertEqual(stored.symbol, "AAPL")
        XCTAssertEqual(stored.notes, "line one\nline two")
        XCTAssertEqual(stored.screenshotList.count, 1)
        XCTAssertFalse(try repo.insertIfNew(bad))
    }

    // MARK: - CSV export (Dojix F7, same code here)

    func testCSVExportNeutralisesCarriageReturnsAndControlCharacters() throws {
        var t = trade(0, profit: 5)
        t.symbol = "AAPL\r=HYPERLINK(\"http://example.invalid\")"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gw-csv-\(UUID().uuidString).csv")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try CSVExporter().export(trades: [t], to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("\r"), "A bare CR splits the row in spreadsheets")
        XCTAssertEqual(text.split(separator: "\n", omittingEmptySubsequences: false).count, 2)
        for line in text.split(separator: "\n") {
            for cell in GenericCSVParser.parseCSVLine(String(line)) {
                XCTAssertFalse(cell.hasPrefix("="), "Formula cell in export: \(cell)")
            }
        }
        // A field that still has an LF or CR after cleaning is quoted
        XCTAssertEqual(CSVExporter.sanitizeCSVField("a\u{0000}b\u{001B}c"), "abc")
        XCTAssertEqual(CSVExporter.sanitizeCSVField("\r-cmd"), "'-cmd")
    }

    // MARK: - Screenshot filenames (Dojix F8, same code here)

    func testOnlyTheAppsOwnScreenshotNamesAreAccepted() {
        let manager = ScreenshotManager.shared
        let good = "\(UUID().uuidString).jpg"
        let dir = manager.screenshotDir(for: 42).standardizedFileURL
        XCTAssertEqual(manager.imageURL(filename: good, for: 42)?.deletingLastPathComponent().standardizedFileURL, dir)
        for hostile in ["..", ".", ".hidden.jpg", "../\(good)", "/etc/passwd", "shot.jpg", "", "\(good)/..",
                        "\(UUID().uuidString).jpg.exe", "\(UUID().uuidString).png"] {
            XCTAssertNil(manager.imageURL(filename: hostile, for: 42), "Accepted \(hostile)")
        }
        XCTAssertThrowsError(try manager.deleteImage(filename: "..", for: 42))
    }
}
