import Foundation
import GRDB

/// Checks a backup before it may replace the journal.
///
/// A backup is a whole SQLite database chosen by the user, so it is treated as hostile and
/// never copied page for page. It is opened read-only in memory; its schema must be exactly
/// what Greenwick's own migrations create (same tables, columns, constraints and indexes, no
/// triggers or views); every row must pass the same limits as an import
/// (`Trade.storageViolations`). Only the validated values are returned. The restore then
/// writes them into the journal's own tables (built by the app's migrator), so nothing of
/// the backup's structure ever reaches the journal. Anything else is refused with a message
/// saying why, and the journal stays as it was.
enum BackupValidator {
    /// Largest backup accepted
    static let maxBackupSize = 512 * 1024 * 1024
    /// Most trades a backup may hold
    static let maxRows = 2_000_000

    /// The validated content of a backup
    struct Contents: Sendable {
        let trades: [Trade]
        let checkpoints: [StrategyCheckpoint]
        let settings: [String: String]
    }

    enum ValidationError: LocalizedError, Equatable {
        case notAGreenwickBackup
        case tooLarge
        case damaged
        case unexpectedSchema(String)
        case newerVersion
        case invalidRow(table: String, row: Int, fields: [String])

        var errorDescription: String? {
            switch self {
            case .notAGreenwickBackup:
                "The selected file is not a valid Greenwick backup."
            case .tooLarge:
                "The backup is larger than 512 MB, so it was not restored."
            case .damaged:
                "The backup file is damaged. Your journal was not changed."
            case .unexpectedSchema(let what):
                "The backup contains something a Greenwick backup never has (\(what)), so it was not restored."
            case .newerVersion:
                "This backup was made by a newer version of Greenwick. Update Greenwick, then restore it."
            case .invalidRow(let table, let row, let fields):
                "The backup was not restored: row \(row) of \(table) has values outside what Greenwick "
                    + "accepts (\(fields.joined(separator: ", ")))."
            }
        }
    }

    /// Validate SQLite file bytes and return their trades, checkpoints and settings
    static func validatedContents(from bytes: Data) throws -> Contents {
        guard bytes.count <= maxBackupSize else { throw ValidationError.tooLarge }
        guard DatabaseEncryption.isPlaintextSQLite(bytes), bytes.count >= 100 else {
            throw ValidationError.notAGreenwickBackup
        }

        let backup = try DatabaseQueue()
        defer { try? backup.close() }
        do {
            try backup.writeWithoutTransaction { db in
                try DatabaseManager.deserialize(bytes, into: db, readOnly: true)
            }
        } catch {
            throw ValidationError.notAGreenwickBackup
        }

        return try backup.read { db in
            let applied = try checkHistory(db)
            try checkSchema(db, matches: try referenceSchema(upTo: applied.last ?? "v1_createTrades"))
            return try readContents(db)
        }
    }

    // MARK: - Structure

    /// Migration history: Greenwick's own, applied in order, none from a newer version
    private static func checkHistory(_ db: Database) throws -> [String] {
        let integrity = (try? String.fetchAll(db, sql: "PRAGMA quick_check")) ?? []
        guard integrity == ["ok"] else { throw ValidationError.damaged }
        guard try db.tableExists("grdb_migrations"), try db.tableExists("trades") else {
            throw ValidationError.notAGreenwickBackup
        }
        let applied = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
        let known = DatabaseManager.knownMigrations
        guard applied.contains("v1_createTrades") else { throw ValidationError.notAGreenwickBackup }
        guard Set(applied).isSubset(of: known) else { throw ValidationError.newerVersion }
        guard applied.count == Set(applied).count, Set(applied) == Set(known.prefix(applied.count)) else {
            throw ValidationError.unexpectedSchema("migration history")
        }
        return Array(known.prefix(applied.count))
    }

    /// "type name" → structure signature of every schema object (columns with type,
    /// NOT NULL, default, primary key and hidden/generated flag; index columns and uniqueness). Compared by
    /// structure rather than SQL text, so formatting differences don't matter.
    private typealias Schema = [String: String]

    /// The schema the app's own migrator creates, up to `migration` (older backups)
    private static func referenceSchema(upTo migration: String) throws -> Schema {
        let reference = try DatabaseQueue()
        defer { try? reference.close() }
        try DatabaseManager.makeMigrator().migrate(reference, upTo: migration)
        return try reference.read { try schema(of: $0) }
    }

    private static func value(_ row: Row, _ column: String) -> String {
        let value: DatabaseValue = row[column]
        switch value.storage {
        case .null: return "null"
        case .int64(let int): return String(int)
        case .double(let double): return String(double)
        case .string(let string): return "'\(string)'"
        case .blob(let data): return data.base64EncodedString()
        }
    }

    private static func quoted(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func schema(of db: Database) throws -> Schema {
        var result: Schema = [:]
        for row in try Row.fetchAll(db, sql: "SELECT type, name, tbl_name FROM sqlite_master") {
            let type = text(row, "type") ?? "?"
            let name = text(row, "name") ?? "?"
            let table = text(row, "tbl_name") ?? "?"
            switch type {
            case "table":
                // table_xinfo, not table_info: it also lists generated (hidden) columns, which a
                // hostile backup could add and which are computed for every row read
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_xinfo(\(quoted(name)))").map { column in
                    ["name", "type", "notnull", "dflt_value", "pk", "hidden"].map { value(column, $0) }
                        .joined(separator: " ")
                }
                result["table \(name)"] = columns.joined(separator: "; ")
            case "index":
                let columns = try Row.fetchAll(db, sql: "PRAGMA index_xinfo(\(quoted(name)))").map { column in
                    ["seqno", "name", "desc", "coll", "key"].map { value(column, $0) }.joined(separator: " ")
                }
                let unique = try Row.fetchAll(db, sql: "PRAGMA index_list(\(quoted(table)))")
                    .first { text($0, "name") == name }
                    .map { value($0, "unique") } ?? "?"
                result["index \(name)"] = "on \(table) unique \(unique): " + columns.joined(separator: "; ")
            default:
                result["\(type) \(name)"] = type // triggers, views: never in the reference
            }
        }
        return result
    }

    /// The backup's schema must be exactly the app's: an allowed table name with other
    /// columns, constraints or defaults, an extra index, a trigger or a view is refused
    private static func checkSchema(_ db: Database, matches reference: Schema) throws {
        let actual = try schema(of: db)
        for (object, signature) in actual.sorted(by: { $0.key < $1.key }) {
            guard let expected = reference[object] else { throw ValidationError.unexpectedSchema(object) }
            guard expected == signature else { throw ValidationError.unexpectedSchema("\(object) definition") }
        }
        // sqlite_sequence only exists once a row was inserted
        for object in reference.keys where actual[object] == nil && object != "table sqlite_sequence" {
            throw ValidationError.unexpectedSchema("missing \(object)")
        }
    }

    // MARK: - Rows

    /// A text column, or nil if it holds anything else (never traps on a hostile type)
    private static func text(_ row: Row, _ column: String) -> String? {
        let value: DatabaseValue = row[column]
        guard case .string(let string) = value.storage else { return nil }
        return string
    }

    private static func readContents(_ db: Database) throws -> Contents {
        guard try Trade.fetchCount(db) <= maxRows else { throw ValidationError.tooLarge }
        var trades: [Trade] = []
        // Backups from before v5 have no isSample column: mark their sample trades the same
        // way the migration does
        let hasSampleFlag = try db.columns(in: "trades").contains { $0.name == "isSample" }
        let sql = hasSampleFlag
            ? "SELECT * FROM trades ORDER BY rowid"
            : """
              SELECT *, (comment IN ('Demo', '\(DemoDataGenerator.sampleComment)')
                         AND ticket BETWEEN 900000 AND 900029) AS isSample
              FROM trades ORDER BY rowid
              """
        let cursor = try Row.fetchCursor(db, sql: sql)
        var index = 0
        while let row = try cursor.next() {
            index += 1
            let trade: Trade
            do {
                trade = try Trade(row: row)
            } catch {
                throw ValidationError.invalidRow(table: "trades", row: index, fields: ["unreadable value"])
            }
            var bad = trade.storageViolations + trade.controlCharacterFields
            if (trade.id ?? 0) <= 0 { bad.append("id") }
            guard bad.isEmpty else {
                throw ValidationError.invalidRow(table: "trades", row: index, fields: Array(Set(bad)).sorted())
            }
            trades.append(trade)
        }

        var checkpoints: [StrategyCheckpoint] = []
        if try db.tableExists("strategy_checkpoints") {
            let rows = try Row.fetchCursor(db, sql: "SELECT * FROM strategy_checkpoints ORDER BY rowid")
            var n = 0
            while let row = try rows.next() {
                n += 1
                guard let title = text(row, "title"), let body = text(row, "description"),
                      let checkpoint = try? StrategyCheckpoint(row: row),
                      title.count <= TradeLimits.maxLabelLength, body.count <= TradeLimits.maxTextLength,
                      !title.containsControlCharacters(allowingLineBreaks: false),
                      !body.containsControlCharacters(allowingLineBreaks: true),
                      TradeLimits.dateRange.contains(checkpoint.date.timeIntervalSince1970),
                      TradeLimits.dateRange.contains(checkpoint.createdAt.timeIntervalSince1970) else {
                    throw ValidationError.invalidRow(table: "strategy_checkpoints", row: n,
                                                     fields: ["title/description/date"])
                }
                checkpoints.append(checkpoint)
            }
        }

        var settings: [String: String] = [:]
        if try db.tableExists("settings") {
            let rows = try Row.fetchCursor(db, sql: "SELECT key, value FROM settings")
            var n = 0
            while let row = try rows.next() {
                n += 1
                guard let key = text(row, "key"), let value = text(row, "value"),
                      key.count <= TradeLimits.maxLabelLength, value.count <= TradeLimits.maxTextLength,
                      !key.containsControlCharacters(allowingLineBreaks: false) else {
                    throw ValidationError.invalidRow(table: "settings", row: n, fields: ["key/value"])
                }
                settings[key] = value
            }
        }
        return Contents(trades: trades, checkpoints: checkpoints, settings: settings)
    }
}
