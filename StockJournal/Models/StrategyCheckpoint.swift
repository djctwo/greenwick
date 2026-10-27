import Foundation
import GRDB

/// A user-defined strategy change marker for before/after comparison
struct StrategyCheckpoint: Codable, Identifiable, Sendable {
    var id: Int64?
    var date: Date
    var title: String
    var description: String
    var createdAt: Date

    init(id: Int64? = nil, date: Date, title: String, description: String = "", createdAt: Date = Date()) {
        self.id = id
        self.date = date
        self.title = title
        self.description = description
        self.createdAt = createdAt
    }
}

// MARK: - GRDB Record Conformance

extension StrategyCheckpoint: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "strategy_checkpoints"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
