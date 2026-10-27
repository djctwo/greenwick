import GRDB

extension DatabaseManager {
    // MARK: - Migrations

    /// The app's migrations, in order. Migrations already applied by a newer version are
    /// left alone; nothing here ever erases a database.
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createTrades") { db in
            try db.create(table: "trades") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ticket", .integer).notNull().unique()
                t.column("symbol", .text).notNull()
                t.column("direction", .text).notNull()
                t.column("shares", .double).notNull()
                t.column("openTime", .datetime).notNull()
                t.column("closeTime", .datetime).notNull()
                t.column("durationMin", .integer).notNull()
                t.column("openPrice", .text).notNull()
                t.column("closePrice", .text).notNull()
                t.column("sl", .text).notNull()
                t.column("tp", .text).notNull()
                t.column("netProfit", .text).notNull()
                t.column("maePoints", .double).notNull()
                t.column("mfePoints", .double).notNull()
                t.column("rMultiple", .double).notNull()
                t.column("session", .text).notNull()
                t.column("dayOfWeek", .text).notNull()
                t.column("hour", .integer).notNull()
                t.column("rangeSize", .double).notNull()
                t.column("hitBreakeven", .boolean).notNull()
                t.column("scaledIn", .boolean).notNull()
                t.column("comment", .text).notNull().defaults(to: "")
                t.column("timeToMFEMin", .integer).notNull().defaults(to: 0)
                t.column("slDistPoints", .double).notNull().defaults(to: 0)
                t.column("slippagePoints", .double).notNull().defaults(to: 0)
                t.column("sector", .text).notNull().defaults(to: "")
                t.column("industry", .text).notNull().defaults(to: "")
                t.column("volume", .integer).notNull().defaults(to: 0)
                t.column("avgVolume", .integer).notNull().defaults(to: 0)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("emotion", .text).notNull().defaults(to: "")
                t.column("commission", .text).notNull().defaults(to: "0")
                t.column("swap", .text).notNull().defaults(to: "0")
                t.column("screenshots", .text).notNull().defaults(to: "")
                t.column("checklistData", .text).notNull().defaults(to: "")
                t.column("importedAt", .datetime).notNull()
            }

            try db.create(index: "idx_trades_symbol", on: "trades", columns: ["symbol"])
            try db.create(index: "idx_trades_session", on: "trades", columns: ["session"])
            try db.create(index: "idx_trades_openTime", on: "trades", columns: ["openTime"])
            try db.create(index: "idx_trades_hour", on: "trades", columns: ["hour"])
            try db.create(index: "idx_trades_sector", on: "trades", columns: ["sector"])
        }

        migrator.registerMigration("v2_createStrategyCheckpoints") { db in
            try db.create(table: "strategy_checkpoints") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_checkpoints_date", on: "strategy_checkpoints", columns: ["date"])
        }

        migrator.registerMigration("v3_addPerformanceIndexes") { db in
            try db.create(index: "idx_trades_direction", on: "trades", columns: ["direction"])
            try db.create(index: "idx_trades_dayOfWeek", on: "trades", columns: ["dayOfWeek"])
            try db.create(index: "idx_trades_closeTime", on: "trades", columns: ["closeTime"])
            try db.create(index: "idx_trades_symbol_closeTime", on: "trades", columns: ["symbol", "closeTime"])
            try db.create(index: "idx_trades_ticket", on: "trades", columns: ["ticket"], unique: true)
        }

        migrator.registerMigration("v4_createSettings") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v5_markSampleTrades") { db in
            try db.alter(table: "trades") { t in
                t.add(column: "isSample", .boolean).notNull().defaults(to: false)
            }
            // Sample trades loaded by earlier versions: their fixed tickets and comment
            try db.execute(sql: DemoDataGenerator.legacySampleMarkingSQL)
        }

        return migrator
    }

    /// Migration identifiers this version knows, in order
    static var knownMigrations: [String] { makeMigrator().migrations }
}
