import Foundation
import GRDB
import os

/// ViewModel for the Dashboard view with portfolio metrics and charts
@Observable
@MainActor
final class DashboardViewModel {
    private let repository: TradeRepository
    private let database: DatabaseManager
    private nonisolated static let logger = Logger(subsystem: "com.greenwick", category: "DashboardVM")

    /// All trades from the database
    private var allTrades: [Trade] = []

    /// Date range filter — defaults to all time
    var selectedDateRange: DateRange = .all {
        didSet { recalculate() }
    }

    /// Symbol filter — nil means all symbols
    var selectedSymbol: String? {
        didSet { recalculate() }
    }

    /// Available symbols for filter picker
    var availableSymbols: [String] {
        Array(Set(allTrades.map(\.symbol))).sorted()
    }

    enum DashboardCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case overview = "Overview"
        case timing = "Timing"
        case sessions = "Sessions"
        case symbols = "Symbols"
        case risk = "Risk"
        case behavioral = "Behavioral"
        case advanced = "Advanced"
        case propFirm = "Prop Firm"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: "square.grid.2x2"
            case .overview: "gauge.with.dots.needle.33percent"
            case .timing: "clock"
            case .sessions: "globe"
            case .symbols: "chart.bar"
            case .risk: "shield.lefthalf.filled"
            case .behavioral: "brain.head.profile"
            case .advanced: "wand.and.stars"
            case .propFirm: "building.columns"
            }
        }

        /// One-line context shown at the top of each analytics category
        var subtitle: String? {
            switch self {
            case .timing: "When you trade — hourly patterns, day-of-week, duration, gaps"
            case .sessions: "Session-level performance, edge breakdowns, kill zones"
            case .symbols: "What you trade — win/loss, share sizing, sector exposure"
            case .risk: "Drawdown, Monte Carlo, position sizing, execution quality"
            case .behavioral: "Discipline, consistency, emotions, checklists"
            case .advanced: "Edge decay, regime analysis, earnings impact, correlations"
            case .propFirm: "Challenge progress, daily loss limits, drawdown tracking"
            default: nil
            }
        }
    }

    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All Time"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30 = "Last 30 Days"
        case last90 = "Last 90 Days"

        var id: String { rawValue }
    }

    /// Filtered trades based on date range and symbol
    var trades: [Trade] {
        var result = allTrades

        if selectedDateRange != .all {
            let cutoff = dateRangeCutoff
            result = result.filter { $0.closeTime >= cutoff }
        }

        if let symbol = selectedSymbol {
            result = result.filter { $0.symbol == symbol }
        }

        return result
    }

    var metrics: MetricsCalculator.PortfolioMetrics = .empty
    var equityCurve: [(date: Date, cumulative: Double)] = []
    var edgeBySession: [MetricsCalculator.EdgeBreakdown] = []
    var edgeByHour: [MetricsCalculator.EdgeBreakdown] = []
    var edgeBySymbol: [MetricsCalculator.EdgeBreakdown] = []
    var edgeByDay: [MetricsCalculator.EdgeBreakdown] = []
    var isLoading = false

    // MARK: - Strategy Checkpoints

    private let checkpointRepository: CheckpointRepository
    var checkpoints: [StrategyCheckpoint] = []

    private var observation: AnyDatabaseCancellable?
    private var checkpointObservation: AnyDatabaseCancellable?

    init(repository: TradeRepository, database: DatabaseManager) {
        self.repository = repository
        self.database = database
        self.checkpointRepository = CheckpointRepository(database: database)
        startObserving()
    }

    private func startObserving() {
        self.observation = repository.observeAll(
            onError: { error in
                Self.logger.error("Dashboard observation error: \(error.localizedDescription)")
            },
            onChange: { [weak self] trades in
                Task { @MainActor in
                    self?.allTrades = trades
                    self?.recalculate()
                }
            }
        )

        self.checkpointObservation = checkpointRepository.observeAll(
            onError: { error in
                Self.logger.error("Checkpoint observation error: \(error.localizedDescription)")
            },
            onChange: { [weak self] checkpoints in
                Task { @MainActor in
                    self?.checkpoints = checkpoints
                }
            }
        )
    }

    func addCheckpoint(_ checkpoint: StrategyCheckpoint) {
        do {
            try checkpointRepository.insert(checkpoint)
        } catch {
            Self.logger.error("Failed to add checkpoint: \(error.localizedDescription)")
        }
    }

    func deleteCheckpoint(id: Int64) {
        do {
            try checkpointRepository.delete(id: id)
        } catch {
            Self.logger.error("Failed to delete checkpoint: \(error.localizedDescription)")
        }
    }

    private func recalculate() {
        let filtered = trades
        metrics = MetricsCalculator.calculate(from: filtered)
        edgeBySession = MetricsCalculator.edgeBySession(from: filtered)
        edgeByHour = MetricsCalculator.edgeByHour(from: filtered)
        edgeBySymbol = MetricsCalculator.edgeBySymbol(from: filtered)
        edgeByDay = MetricsCalculator.edgeByDay(from: filtered)

        // Build equity curve from filtered trades
        var cumulative = 0.0
        equityCurve = filtered
            .sorted { $0.closeTime < $1.closeTime }
            .map { trade in
                cumulative += trade.profitDouble
                return (date: trade.closeTime, cumulative: cumulative)
            }
    }

    func refresh() {
        do {
            allTrades = try repository.fetchAll()
            recalculate()
        } catch {
            Self.logger.error("Failed to refresh: \(error.localizedDescription)")
        }
    }

    /// This week (from Monday) and this month start at New York midnight, like the P&L calendar
    private var dateRangeCutoff: Date {
        let calendar = TradingCalendar.calendar
        let now = Date()
        switch selectedDateRange {
        case .all: return .distantPast
        case .thisWeek: return TradingCalendar.startOfWeek(now)
        case .thisMonth: return TradingCalendar.startOfMonth(now)
        case .last30: return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90: return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        }
    }
}
