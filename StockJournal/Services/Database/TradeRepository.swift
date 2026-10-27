import Foundation
import GRDB
import os

/// All trade database operations go through this repository
final class TradeRepository: Sendable {
    private let database: DatabaseManager
    private static let logger = Logger(subsystem: "com.greenwick", category: "TradeRepository")

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Write

    /// Insert a trade, skipping if ticket already exists or a value is outside
    /// `TradeLimits`. Returns true if inserted.
    @discardableResult
    func insertIfNew(_ trade: Trade) throws -> Bool {
        guard var t = trade.sanitizedForStorage() else {
            Self.logger.warning("Refused a trade with out-of-range values")
            return false
        }
        return try database.dbQueue.write { db in
            let exists = try Trade.filter(Column("ticket") == t.ticket).fetchCount(db) > 0
            if exists { return false }
            try t.insert(db)
            return true
        }
    }

    /// Bulk insert trades, skipping duplicates and trades with values outside
    /// `TradeLimits` (text is cleaned of control characters). Returns count of newly
    /// inserted trades.
    func bulkInsert(_ input: [Trade]) throws -> Int {
        let trades = input.compactMap { $0.sanitizedForStorage() }
        if trades.count < input.count {
            Self.logger.warning("Refused \(input.count - trades.count) trades with out-of-range values")
        }
        return try database.dbQueue.write { db in
            // Batch-check existing tickets with parameterized queries, chunked so the
            // statement stays below SQLite's bound-parameter limit on any SQLite build.
            let tickets = Array(Set(trades.map(\.ticket)))
            var existingTickets = Set<Int64>()
            for start in stride(from: 0, to: tickets.count, by: 500) {
                let chunk = Array(tickets[start..<min(start + 500, tickets.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                existingTickets.formUnion(try Int64.fetchAll(
                    db,
                    sql: "SELECT ticket FROM trades WHERE ticket IN (\(placeholders))",
                    arguments: StatementArguments(chunk)
                ))
            }

            var insertedCount = 0
            for trade in trades {
                // Also skips repeats inside the same batch (would violate the UNIQUE constraint)
                guard existingTickets.insert(trade.ticket).inserted else { continue }
                var t = trade
                try t.insert(db)
                insertedCount += 1
            }
            Self.logger.info("Inserted \(insertedCount) of \(input.count) trades")
            return insertedCount
        }
    }

    /// Add the fictional sample trades. Returns how many were new (0 if already loaded).
    @discardableResult
    func loadSampleTrades() throws -> Int {
        try bulkInsert(DemoDataGenerator.generateTrades())
    }

    /// Delete only the fictional sample trades (never imported or hand-entered ones).
    /// Returns how many were deleted.
    @discardableResult
    func deleteSampleTrades() throws -> Int {
        try database.dbQueue.write { db in
            try Trade.filter(Column("isSample") == true).deleteAll(db)
        }
    }

    /// Number of sample trades in the journal
    func sampleTradeCount() throws -> Int {
        try database.dbQueue.read { db in
            try Trade.filter(Column("isSample") == true).fetchCount(db)
        }
    }

    /// Delete all trades (for testing/reset)
    func deleteAll() throws {
        _ = try database.dbQueue.write { db in
            try Trade.deleteAll(db)
        }
    }

    /// Update trade notes
    func updateNotes(tradeId: Int64, notes: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET notes = ? WHERE id = ?",
                arguments: [String(notes.removingControlCharacters(keepingLineBreaks: true).prefix(TradeLimits.maxTextLength)), tradeId]
            )
        }
    }

    /// Update trade tags
    func updateTags(tradeId: Int64, tags: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET tags = ? WHERE id = ?",
                arguments: [String(tags.removingControlCharacters(keepingLineBreaks: false).prefix(TradeLimits.maxLabelLength)), tradeId]
            )
        }
    }

    /// Update trade emotion
    func updateEmotion(tradeId: Int64, emotion: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET emotion = ? WHERE id = ?",
                arguments: [String(emotion.removingControlCharacters(keepingLineBreaks: false).prefix(TradeLimits.maxLabelLength)), tradeId]
            )
        }
    }

    /// Update trade commission and swap
    /// P&L is stored net of costs, so changing the costs moves the P&L by the difference.
    func updateCosts(tradeId: Int64, commission: Decimal, swap: Decimal) throws {
        try database.dbQueue.write { db in
            guard var trade = try Trade.fetchOne(db, key: tradeId) else { return }
            let costDelta = (commission + swap) - (trade.commission + trade.swap)
            trade.netProfit -= costDelta
            trade.commission = commission
            trade.swap = swap
            guard trade.storageViolations.isEmpty else { throw RepositoryError.valueOutOfRange }
            try trade.update(db)
        }
    }

    /// Update trade screenshots
    func updateScreenshots(tradeId: Int64, screenshots: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET screenshots = ? WHERE id = ?",
                arguments: [Trade.validScreenshotList(screenshots), tradeId]
            )
        }
    }

    /// Update trade checklist data (JSON string)
    func updateChecklist(tradeId: Int64, checklistData: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET checklistData = ? WHERE id = ?",
                arguments: [String(checklistData.removingControlCharacters(keepingLineBreaks: false).prefix(TradeLimits.maxTextLength)), tradeId]
            )
        }
    }

    // MARK: - Read

    /// Fetch all trades, ordered by close time descending
    func fetchAll() throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.order(Column("closeTime").desc).fetchAll(db)
        }
    }

    /// Fetch trades filtered by symbol
    func fetchBySymbol(_ symbol: String) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("symbol") == symbol)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Fetch trades within a date range
    func fetchByDateRange(from: Date, to: Date) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("closeTime") >= from && Column("closeTime") <= to)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Fetch trades by session
    func fetchBySession(_ session: MarketSession) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("session") == session.rawValue)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Count of trades imported this calendar month
    func tradesImportedThisMonth() throws -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return 0
        }
        return try database.dbQueue.read { db in
            try Trade.filter(Column("importedAt") >= startOfMonth).fetchCount(db)
        }
    }

    /// Total trade count
    func count() throws -> Int {
        try database.dbQueue.read { db in
            try Trade.fetchCount(db)
        }
    }

    /// Check if a ticket exists
    func ticketExists(_ ticket: Int64) throws -> Bool {
        try database.dbQueue.read { db in
            try Trade.filter(Column("ticket") == ticket).fetchCount(db) > 0
        }
    }

    // MARK: - Aggregates

    /// Total net profit across all trades
    func totalProfit() throws -> Double {
        try database.dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT CAST(SUM(CAST(netProfit AS REAL)) AS REAL) AS total FROM trades")
            return row?["total"] ?? 0.0
        }
    }

    /// Profit by symbol
    func profitBySymbol() throws -> [(symbol: String, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT symbol,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY symbol
                ORDER BY profit DESC
            """)
            return rows.map { (
                symbol: $0["symbol"] as String,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Profit by session
    func profitBySession() throws -> [(session: String, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT session,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY session
                ORDER BY profit DESC
            """)
            return rows.map { (
                session: $0["session"] as String,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Profit by hour
    func profitByHour() throws -> [(hour: Int, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT hour,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY hour
                ORDER BY hour
            """)
            return rows.map { (
                hour: $0["hour"] as Int,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Equity curve data — cumulative P&L over time
    func equityCurve() throws -> [(date: Date, cumulative: Double)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT closeTime,
                       CAST(netProfit AS REAL) as profit
                FROM trades
                ORDER BY closeTime
            """)
            var cumulative = 0.0
            return rows.map { row in
                let profit: Double = row["profit"]
                cumulative += profit
                return (date: row["closeTime"] as Date, cumulative: cumulative)
            }
        }
    }

    enum RepositoryError: LocalizedError {
        case valueOutOfRange
        var errorDescription: String? { "That amount is outside the range Greenwick can store." }
    }

    // MARK: - Observation (Reactive)

    /// Observe all trades for SwiftUI binding. Returns cancellable.
    @MainActor
    func observeAll(
        onError: @escaping @Sendable (Error) -> Void,
        onChange: @escaping @Sendable ([Trade]) -> Void
    ) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Trade.order(Column("closeTime").desc).fetchAll(db)
            }
            .start(in: database.dbQueue, onError: onError, onChange: onChange)
    }

    /// Observe trade count. Returns cancellable.
    @MainActor
    func observeCount(
        onError: @escaping @Sendable (Error) -> Void,
        onChange: @escaping @Sendable (Int) -> Void
    ) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Trade.fetchCount(db)
            }
            .start(in: database.dbQueue, onError: onError, onChange: onChange)
    }
}
