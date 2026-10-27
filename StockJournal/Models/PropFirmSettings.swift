import Foundation
import GRDB
import os

/// The prop-firm challenge parameters: account size, profit target and loss limits.
///
/// They describe the user's trading account, so they are kept in the encrypted journal
/// (its `settings` table, which backups include) and not in the preferences file, which
/// anyone can read even while App Lock is on. Older versions kept them in UserDefaults;
/// `migrateFromPreferences` moves them once the journal is open.
struct PropFirmSettings: Equatable, Sendable {
    var accountSize: Double
    /// Percentages of the account size
    var profitTarget: Double
    var maxDailyLoss: Double
    var maxTotalDrawdown: Double

    /// Keys in the journal's `settings` table (the same names older versions used in UserDefaults)
    enum Key {
        static let accountSize = "propFirm_accountSize"
        static let profitTarget = "propFirm_profitTarget"
        static let maxDailyLoss = "propFirm_maxDailyLoss"
        static let maxTotalDrawdown = "propFirm_maxTotalDrawdown"
        static let all = [accountSize, profitTarget, maxDailyLoss, maxTotalDrawdown]
    }

    private static let logger = Logger(subsystem: "com.greenwick", category: "PropFirmSettings")

    /// Largest account size accepted (same bound as any amount in a trade)
    static let maxAccountSize = NSDecimalNumber(decimal: TradeLimits.maxAbsAmount).doubleValue

    // MARK: - Validation

    /// The settings with every value outside its range (not finite, not positive, too
    /// large; e.g. from a crafted backup) replaced by its default
    func sanitized() -> PropFirmSettings {
        let defaults = PropFirmSettings()
        func valid(_ value: Double, max: Double, _ fallback: Double) -> Double {
            value.isFinite && value > 0 && value <= max ? value : fallback
        }
        return PropFirmSettings(
            accountSize: valid(accountSize, max: Self.maxAccountSize, defaults.accountSize),
            profitTarget: valid(profitTarget, max: 100, defaults.profitTarget),
            maxDailyLoss: valid(maxDailyLoss, max: 100, defaults.maxDailyLoss),
            maxTotalDrawdown: valid(maxTotalDrawdown, max: 100, defaults.maxTotalDrawdown))
    }

    private var values: [String: Double] {
        [Key.accountSize: accountSize, Key.profitTarget: profitTarget,
         Key.maxDailyLoss: maxDailyLoss, Key.maxTotalDrawdown: maxTotalDrawdown]
    }

    private init(values: [String: Double]) {
        let defaults = PropFirmSettings()
        self.init(accountSize: values[Key.accountSize] ?? defaults.accountSize,
                  profitTarget: values[Key.profitTarget] ?? defaults.profitTarget,
                  maxDailyLoss: values[Key.maxDailyLoss] ?? defaults.maxDailyLoss,
                  maxTotalDrawdown: values[Key.maxTotalDrawdown] ?? defaults.maxTotalDrawdown)
    }

    init(accountSize: Double = 100_000, profitTarget: Double = 8, maxDailyLoss: Double = 5,
         maxTotalDrawdown: Double = 10) {
        self.accountSize = accountSize
        self.profitTarget = profitTarget
        self.maxDailyLoss = maxDailyLoss
        self.maxTotalDrawdown = maxTotalDrawdown
    }

    // MARK: - Journal storage

    /// The saved settings (defaults for anything missing or out of range)
    static func load(from database: DatabaseManager) -> PropFirmSettings {
        do {
            let stored = try database.dbQueue.read { db in
                try Row.fetchAll(db, sql: "SELECT key, value FROM settings WHERE key IN (?, ?, ?, ?)",
                                 arguments: StatementArguments(Key.all))
            }
            var values: [String: Double] = [:]
            for row in stored {
                let key: DatabaseValue = row["key"]
                let value: DatabaseValue = row["value"]
                guard case .string(let name) = key.storage, case .string(let text) = value.storage else { continue }
                values[name] = Double(text)
            }
            return PropFirmSettings(values: values).sanitized()
        } catch {
            logger.error("Could not read the prop firm settings: \(error.localizedDescription)")
            return PropFirmSettings()
        }
    }

    /// Save (out-of-range values are stored as their defaults)
    func save(to database: DatabaseManager) throws {
        let clean = sanitized().values
        try database.dbQueue.write { db in
            for (key, value) in clean {
                try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                               arguments: [key, String(value)])
            }
        }
    }

    /// Move the values an older version kept in `defaults` into the journal (values already
    /// in the journal win) and remove them from `defaults`. Only for a journal that is
    /// saved to disk; nothing is removed if the journal write fails.
    static func migrateFromPreferences(_ defaults: UserDefaults, into database: DatabaseManager) {
        let found = Key.all.filter { defaults.object(forKey: $0) != nil }
        guard database.isPersistent, !found.isEmpty else { return }
        do {
            try database.dbQueue.write { db in
                for key in found {
                    let value = String(defaults.double(forKey: key))
                    try db.execute(sql: "INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)",
                                   arguments: [key, value])
                }
            }
            found.forEach(defaults.removeObject(forKey:))
            logger.notice("Moved the prop firm settings from preferences into the encrypted journal")
        } catch {
            logger.error("Could not move the prop firm settings: \(error.localizedDescription)")
        }
    }
}
