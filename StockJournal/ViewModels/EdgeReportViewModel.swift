import Foundation
import GRDB
import os

/// ViewModel for the Edge Report — surfaces where money is made and lost
@Observable
@MainActor
final class EdgeReportViewModel {
    private let repository: TradeRepository
    private let database: DatabaseManager
    private nonisolated static let logger = Logger(subsystem: "com.greenwick", category: "EdgeReportVM")

    var trades: [Trade] = []
    var isLoading = false

    // Edge breakdowns — top sources of profit and loss
    var topMakersByHour: [MetricsCalculator.EdgeBreakdown] = []
    var topLosersByHour: [MetricsCalculator.EdgeBreakdown] = []
    var topMakersBySession: [MetricsCalculator.EdgeBreakdown] = []
    var topLosersBySession: [MetricsCalculator.EdgeBreakdown] = []
    var topMakersByDay: [MetricsCalculator.EdgeBreakdown] = []
    var topLosersByDay: [MetricsCalculator.EdgeBreakdown] = []
    var topMakersBySymbol: [MetricsCalculator.EdgeBreakdown] = []
    var topLosersBySymbol: [MetricsCalculator.EdgeBreakdown] = []

    // AI analysis
    var aiRecommendations: String?
    var isAnalyzing = false
    var aiError: String?

    // Overall metrics
    var metrics: MetricsCalculator.PortfolioMetrics = .empty
    var hasEnoughData: Bool { trades.count >= Configuration.minimumTradesForAnalysis }

    private var observation: AnyDatabaseCancellable?

    init(repository: TradeRepository, database: DatabaseManager) {
        self.repository = repository
        self.database = database
        startObserving()
    }

    private func startObserving() {
        self.observation = repository.observeAll(
            onError: { error in
                Self.logger.error("EdgeReport observation error: \(error.localizedDescription)")
            },
            onChange: { [weak self] trades in
                Task { @MainActor in
                    self?.trades = trades
                    self?.recalculate()
                }
            }
        )
    }

    private func recalculate() {
        metrics = MetricsCalculator.calculate(from: trades)

        let byHour = MetricsCalculator.edgeByHour(from: trades)
        topMakersByHour = Array(byHour.filter { $0.profit > 0 }.prefix(5))
        topLosersByHour = Array(byHour.filter { $0.profit < 0 }.suffix(5).reversed())

        let bySession = MetricsCalculator.edgeBySession(from: trades)
        topMakersBySession = bySession.filter { $0.profit > 0 }
        topLosersBySession = bySession.filter { $0.profit < 0 }.reversed()

        let byDay = MetricsCalculator.edgeByDay(from: trades)
        topMakersByDay = Array(byDay.filter { $0.profit > 0 }.prefix(5))
        topLosersByDay = Array(byDay.filter { $0.profit < 0 }.suffix(5).reversed())

        let bySymbol = MetricsCalculator.edgeBySymbol(from: trades)
        topMakersBySymbol = bySymbol.filter { $0.profit > 0 }
        topLosersBySymbol = bySymbol.filter { $0.profit < 0 }.reversed()

    }

    // MARK: - AI Analysis

    func runAIAnalysis() async {
        guard hasEnoughData else { return }

        guard Configuration.AI.isEnabled else {
            aiError = "AI analysis is off. Turn it on in Settings > AI Analysis."
            return
        }

        guard let apiKey = KeychainHelper.anthropicAPIKey,
              !apiKey.isEmpty else {
            aiError = "No API key configured. Add your Anthropic API key in Settings."
            return
        }

        isAnalyzing = true
        aiError = nil

        let service = ClaudeService(apiKey: apiKey)
        let prompt = PromptBuilder.edgeAnalysis(from: trades, metrics: metrics)

        do {
            let response = try await service.send(
                system: PromptBuilder.systemPrompt,
                messages: [ClaudeService.Message(role: "user", content: prompt)],
                model: .sonnet
            )
            aiRecommendations = response
        } catch {
            aiError = error.localizedDescription
            Self.logger.error("AI analysis failed: \(error.localizedDescription)")
        }

        isAnalyzing = false
    }
}
