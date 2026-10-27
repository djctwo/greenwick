import Foundation
import GRDB

/// Represents a single trade imported from broker CSV or manual entry
struct Trade: Codable, Identifiable, Sendable {
    // MARK: - Core Fields

    var id: Int64?
    var ticket: Int64
    var symbol: String
    var direction: TradeDirection
    var shares: Double
    var openTime: Date
    var closeTime: Date
    var durationMin: Int
    var openPrice: Decimal
    var closePrice: Decimal
    var sl: Decimal
    var tp: Decimal
    var netProfit: Decimal

    // MARK: - Computed Metrics

    var maePoints: Double
    var mfePoints: Double
    var rMultiple: Double
    var session: MarketSession
    var dayOfWeek: String
    var hour: Int
    var rangeSize: Double
    var hitBreakeven: Bool
    var scaledIn: Bool
    var comment: String

    // MARK: - Advanced Metrics

    var timeToMFEMin: Int
    var slDistPoints: Double
    var slippagePoints: Double

    // MARK: - Stock-Specific

    var sector: String = ""       // e.g., "Technology", "Energy"
    var industry: String = ""     // e.g., "Semiconductors", "Oil & Gas"
    var volume: Int = 0           // Trade volume
    var avgVolume: Int = 0        // Average daily volume of symbol

    // MARK: - User Annotations

    var notes: String = ""
    var tags: String = ""         // Comma-separated tags
    var emotion: String = ""      // Pre-trade emotional state
    var screenshots: String = ""  // Comma-separated filenames
    var checklistData: String = "" // JSON: {"rule": true/false}

    // MARK: - Costs

    var commission: Decimal = 0
    var swap: Decimal = 0

    // MARK: - Import Metadata

    var importedAt: Date

    /// One of the fictional sample trades (Settings > Load Sample Trades). Only these are
    /// removed by "Remove Sample Trades"; imported and hand-entered trades are never marked.
    var isSample: Bool = false
}

// MARK: - Enums

enum TradeDirection: String, Codable, DatabaseValueConvertible, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

extension TradeDirection: Comparable {
    static func < (lhs: TradeDirection, rhs: TradeDirection) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MarketSession: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable {
    case preMarket = "PRE_MARKET"
    case regular = "REGULAR"
    case afterHours = "AFTER_HOURS"
    case extended = "EXTENDED"

    var displayName: String {
        switch self {
        case .preMarket: "Pre-Market"
        case .regular: "Regular"
        case .afterHours: "After Hours"
        case .extended: "Extended"
        }
    }

    /// Sessions whose tagged trades are relevant to this session's analysis
    var relatedSessions: Set<MarketSession> {
        switch self {
        case .regular: [.regular]
        case .preMarket: [.preMarket]
        case .afterHours: [.afterHours]
        case .extended: [.extended, .preMarket, .afterHours]
        }
    }

    /// Session start hour in exchange time (24h), from `Market.default`
    var startHourET: Int {
        let market = Market.default
        switch self {
        case .preMarket, .extended: return market.preMarketOpen / 60
        case .regular: return market.regularOpen / 60   // 9 (opens 9:30)
        case .afterHours: return market.regularClose / 60
        }
    }

    /// Session end hour in exchange time (24h), from `Market.default`
    var endHourET: Int {
        let market = Market.default
        switch self {
        case .preMarket: return market.regularOpen / 60   // 9 (ends 9:30)
        case .regular: return market.regularClose / 60
        case .afterHours, .extended: return market.afterHoursClose / 60
        }
    }
}

extension MarketSession: Comparable {
    static func < (lhs: MarketSession, rhs: MarketSession) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Pre-trade emotional state for tiltmeter tracking
enum TradeEmotion: String, Codable, CaseIterable, Sendable {
    case calm = "CALM"
    case confident = "CONFIDENT"
    case anxious = "ANXIOUS"
    case frustrated = "FRUSTRATED"
    case revenge = "REVENGE"
    case fomo = "FOMO"
    case bored = "BORED"

    var displayName: String {
        switch self {
        case .calm: "Calm"
        case .confident: "Confident"
        case .anxious: "Anxious"
        case .frustrated: "Frustrated"
        case .revenge: "Revenge"
        case .fomo: "FOMO"
        case .bored: "Bored"
        }
    }

    var icon: String {
        switch self {
        case .calm: "leaf.fill"
        case .confident: "bolt.fill"
        case .anxious: "exclamationmark.triangle.fill"
        case .frustrated: "flame.fill"
        case .revenge: "arrow.counterclockwise"
        case .fomo: "clock.badge.exclamationmark.fill"
        case .bored: "zzz"
        }
    }

    var color: String {
        switch self {
        case .calm: "green"
        case .confident: "blue"
        case .anxious: "yellow"
        case .frustrated: "orange"
        case .revenge: "red"
        case .fomo: "purple"
        case .bored: "gray"
        }
    }
}

// MARK: - GRDB Record Conformance

extension Trade: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "trades"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Computed Properties

extension Trade {
    var isWin: Bool { netProfit > 0 }
    var isLoss: Bool { netProfit < 0 }
    var profitDouble: Double { NSDecimalNumber(decimal: netProfit).doubleValue }

    var directionSymbol: String {
        direction == .buy ? "↑" : "↓"
    }

    /// Ticker display (already a clean symbol like AAPL, TSLA)
    var tickerDisplay: String { symbol }

    /// Parsed tags from comma-separated string
    var tagList: [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Add a tag
    func withTag(_ tag: String) -> Trade {
        var copy = self
        var existing = copy.tagList
        if !existing.contains(tag) {
            existing.append(tag)
            copy.tags = existing.joined(separator: ",")
        }
        return copy
    }

    /// Remove a tag
    func withoutTag(_ tag: String) -> Trade {
        var copy = self
        copy.tags = copy.tagList.filter { $0 != tag }.joined(separator: ",")
        return copy
    }

    /// Parsed emotion from stored string
    var tradeEmotion: TradeEmotion? {
        guard !emotion.isEmpty else { return nil }
        return TradeEmotion(rawValue: emotion)
    }

    /// P&L before commissions and swap (`netProfit` already has costs taken off)
    var grossProfitBeforeCosts: Decimal {
        netProfit + commission + swap
    }

    /// Commission as Double
    var commissionDouble: Double {
        NSDecimalNumber(decimal: commission).doubleValue
    }

    /// Swap as Double
    var swapDouble: Double {
        NSDecimalNumber(decimal: swap).doubleValue
    }

    /// Total costs (commission + swap)
    var totalCosts: Double {
        commissionDouble + swapDouble
    }

    /// Parsed screenshot filenames
    var screenshotList: [String] {
        screenshots.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Parsed checklist compliance data
    var checklistResults: [String: Bool] {
        guard !checklistData.isEmpty,
              let data = checklistData.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Exit efficiency: how much of MFE was captured (0-100%)
    var exitEfficiency: Double? {
        guard mfePoints > 0, slDistPoints > 0 else { return nil }
        let capturedPoints = rMultiple * slDistPoints
        return min(max(capturedPoints / mfePoints * 100, 0), 100)
    }

    /// Money left on table: MFE minus actual profit in points
    var moneyLeftOnTable: Double? {
        guard mfePoints > 0, isWin else { return nil }
        let capturedPoints = rMultiple * slDistPoints
        return max(mfePoints - capturedPoints, 0)
    }
}
