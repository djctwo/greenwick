import GRDB
import XCTest
@testable import Greenwick

/// Load / Remove Sample Trades: 30 fictional trades, loaded once, removable without ever
/// touching real (imported or hand-entered) trades.
final class SampleTradesTests: XCTestCase {

    private func makeRepository() throws -> TradeRepository {
        TradeRepository(database: try DatabaseManager(inMemory: true))
    }

    func testLoadingAddsThe30SampleTradesWithTheKnownHeadline() throws {
        let repo = try makeRepository()
        XCTAssertEqual(try repo.loadSampleTrades(), 30)
        let trades = try repo.fetchAll()
        XCTAssertEqual(trades.count, 30)
        XCTAssertTrue(trades.allSatisfy { $0.isSample && $0.comment == DemoDataGenerator.sampleComment })
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(metrics.totalProfit.asCurrency, "$1,975.00")
        XCTAssertEqual(String(format: "%.1f%%", metrics.winRate), "66.7%")
    }

    func testLoadingTwiceDoesNotDuplicate() throws {
        let repo = try makeRepository()
        XCTAssertEqual(try repo.loadSampleTrades(), 30)
        XCTAssertEqual(try repo.loadSampleTrades(), 0)
        XCTAssertEqual(try repo.count(), 30)
        XCTAssertEqual(try repo.sampleTradeCount(), 30)
    }

    func testRemovingDeletesOnlyTheSampleTrades() throws {
        let repo = try makeRepository()
        // A real trade, even one that looks like a sample (same comment, nearby ticket)
        var real = DemoDataGenerator.generateTrades()[3]
        real.ticket = DemoDataGenerator.ticketBase + 30
        real.isSample = false
        real.notes = "my own trade"
        var lookalike = real
        lookalike.ticket = 4_242
        lookalike.comment = DemoDataGenerator.sampleComment
        XCTAssertEqual(try repo.bulkInsert([real, lookalike]), 2)
        XCTAssertEqual(try repo.loadSampleTrades(), 30)

        XCTAssertEqual(try repo.deleteSampleTrades(), 30)
        let left = try repo.fetchAll()
        XCTAssertEqual(Set(left.map(\.ticket)), [real.ticket, 4_242])
        XCTAssertTrue(left.allSatisfy { $0.notes == "my own trade" && !$0.isSample })
        XCTAssertEqual(try repo.deleteSampleTrades(), 0)
    }

    func testImportedTradesAreNeverSamples() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gw-sample-\(UUID().uuidString).csv")
        try """
        Exec Time,Symbol,Side,Qty,Price,Net Price,P/L,Commission
        03/24/26 09:31:15,AAPL,BUY,100,171.25,171.30,25.00,0.65
        """.write(to: path, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        let detection = try GenericCSVParser.detect(fileAt: path.path)
        let trades = try GenericCSVParser.parse(fileAt: path.path, mapping: try XCTUnwrap(detection.mapping))
        XCTAssertFalse(trades.isEmpty)
        XCTAssertTrue(trades.allSatisfy { !$0.isSample })
    }

    /// Journals from earlier versions: sample trades had comment "Demo" and tickets
    /// 900000-900029; the migration marks exactly those
    func testMigrationMarksSampleTradesFromEarlierVersions() throws {
        let queue = try DatabaseQueue()
        try DatabaseManager.makeMigrator().migrate(queue, upTo: "v4_createSettings")
        try queue.write { db in
            let insert = """
                INSERT INTO trades (ticket, symbol, direction, shares, openTime, closeTime, durationMin,
                  openPrice, closePrice, sl, tp, netProfit, maePoints, mfePoints, rMultiple, session,
                  dayOfWeek, hour, rangeSize, hitBreakeven, scaledIn, comment, importedAt)
                VALUES (?, 'AAPL', 'BUY', 1, '2026-03-24 14:00:00', '2026-03-24 14:30:00', 30,
                  '1', '2', '0', '0', '1', 0, 0, 0, 'REGULAR', 'Tue', 10, 0, 0, 0, ?, '2026-03-24 14:00:00')
                """
            try db.execute(sql: insert, arguments: [900_000, "Demo"])
            try db.execute(sql: insert, arguments: [900_029, "Demo"])
            try db.execute(sql: insert, arguments: [900_030, "Demo"])     // outside the sample range
            try db.execute(sql: insert, arguments: [900_001, "my note"])  // a user's own trade
        }
        try DatabaseManager.makeMigrator().migrate(queue)
        let marked = try queue.read { try Int64.fetchAll($0, sql: "SELECT ticket FROM trades WHERE isSample ORDER BY ticket") }
        XCTAssertEqual(marked, [900_000, 900_029])
    }
}
