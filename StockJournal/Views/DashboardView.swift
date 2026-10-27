import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let category: DashboardViewModel.DashboardCategory
    @Environment(\.appState) private var appState

    var body: some View {
        Group {
            if viewModel.trades.isEmpty {
                EmptyStateView(
                    icon: "chart.bar.xaxis",
                    title: "No Data Yet",
                    message: "Import trades to see your portfolio dashboard with equity curve, metrics, and edge breakdowns.",
                    actionTitle: "Go to Import"
                ) {
                    appState.selectedTab = .importTrades
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let subtitle = category.subtitle {
                            Text(subtitle)
                                .font(.bodyText)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        switch category {
                        case .all:
                            allContent
                        case .overview:
                            overviewContent
                        case .timing:
                            timingContent
                        case .sessions:
                            sessionsContent
                        case .symbols:
                            symbolsContent
                        case .risk:
                            riskContent
                        case .behavioral:
                            behavioralContent
                        case .advanced:
                            advancedContent
                        case .propFirm:
                            propFirmContent
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(category == .overview ? "Dashboard" : category.rawValue)
        .toolbar {
            if !viewModel.trades.isEmpty || viewModel.selectedSymbol != nil {
                ToolbarItem {
                    Picker("Symbol", selection: $viewModel.selectedSymbol) {
                        Text("All Symbols").tag(nil as String?)
                        ForEach(viewModel.availableSymbols, id: \.self) { symbol in
                            Text(symbol).tag(symbol as String?)
                        }
                    }
                    .frame(width: 110)
                }
                ToolbarItem {
                    Picker("Period", selection: $viewModel.selectedDateRange) {
                        ForEach(DashboardViewModel.DateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .frame(width: 130)
                }
                ToolbarItem {
                    Menu {
                        Button {
                            exportDashboardPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            exportDashboardCSV()
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.smallText)
                    }
                }
            }
        }
    }

    // MARK: - All Content (original full dashboard)

    @ViewBuilder
    private var allContent: some View {
        overviewContent
        timingContent
        sessionsContent
        symbolsContent
        riskContent
        behavioralContent
        advancedContent
        propFirmContent
    }

    // MARK: - Overview (morning briefing — 4 key components only)

    @ViewBuilder
    private var overviewContent: some View {
        // Daily Brief — top 3 actionable signals
        DailyBrief(trades: viewModel.trades, metrics: viewModel.metrics)

        // Key metrics — always visible
        metricsGrid

        // Prop firm status — above the fold for prop firm traders
        PropFirmStatusBadge(trades: viewModel.trades)

        // Equity curve — the most important chart
        equityCurveChart

        // Quick performance snapshot — inline, compact
        HStack(spacing: 16) {
            SessionRankingCard(trades: viewModel.trades)
                .frame(minWidth: 0, maxWidth: .infinity)
            StreakCard(trades: viewModel.trades)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
    }

    // MARK: - Timing (when you trade)

    @ViewBuilder
    private var timingContent: some View {
        TradeCalendar(trades: viewModel.trades)
        HourlyPnLChart(trades: viewModel.trades)
        equalHeightRow {
            DayOfWeekChart(trades: viewModel.trades)
        } right: {
            DurationAnalysis(trades: viewModel.trades)
        }
        TradeTimeHeatmap(trades: viewModel.trades)
        WeeklyHeatmap(trades: viewModel.trades)
        OpeningRangeAnalysis(trades: viewModel.trades)
        GapAnalysis(trades: viewModel.trades)
    }

    // MARK: - Sessions (session-level edge)

    @ViewBuilder
    private var sessionsContent: some View {
        secondaryMetricsRow
        PerformanceSummary(trades: viewModel.trades)
        PeriodComparison(trades: viewModel.trades)
        equalHeightRow {
            SessionHeatmap(trades: viewModel.trades)
        } right: {
            RMultipleChart(trades: viewModel.trades)
        }
        equalHeightRow {
            SessionIntelligence(trades: viewModel.trades)
        } right: {
            SequenceAnalysis(trades: viewModel.trades)
        }
        StreakTimeline(trades: viewModel.trades)
        KillZoneOptimizer(trades: viewModel.trades)
        WhatToCutAdvisor(trades: viewModel.trades)
        edgeBreakdowns
    }

    // MARK: - Symbols (what/how you trade)

    @ViewBuilder
    private var symbolsContent: some View {
        equalHeightRow {
            WinLossDistribution(trades: viewModel.trades)
        } right: {
            SymbolAnalytics(trades: viewModel.trades)
        }
        equalHeightRow {
            ShareSizeAnalysis(trades: viewModel.trades)
        } right: {
            MAEMFEChart(trades: viewModel.trades)
        }
        equalHeightRow {
            DirectionalEdge(trades: viewModel.trades)
        } right: {
            SlippageAnalysis(trades: viewModel.trades)
        }
        SectorExposure(trades: viewModel.trades)
        VolumeAnalysis(trades: viewModel.trades)
        DiversificationScore(trades: viewModel.trades)
    }

    // MARK: - Risk (risk management)

    @ViewBuilder
    private var riskContent: some View {
        DrawdownChart(trades: viewModel.trades)
        MonthlyReturns(trades: viewModel.trades)
        equalHeightRow {
            RiskOfRuin(trades: viewModel.trades)
        } right: {
            BehavioralAnalytics(trades: viewModel.trades)
        }
        MonteCarloSimulation(trades: viewModel.trades)
        DrawdownRecovery(trades: viewModel.trades)
        equalHeightRow {
            GrowthProjection(trades: viewModel.trades, metrics: viewModel.metrics)
        } right: {
            PositionSizer(trades: viewModel.trades, metrics: viewModel.metrics)
        }
        ExpectancyCurve(trades: viewModel.trades, metrics: viewModel.metrics)
        equalHeightRow {
            ExitAnalysis(trades: viewModel.trades)
        } right: {
            CommissionAnalytics(trades: viewModel.trades)
        }
        ExecutionQuality(trades: viewModel.trades)
    }

    // MARK: - Behavioral (discipline & psychology)

    @ViewBuilder
    private var behavioralContent: some View {
        equalHeightRow {
            GradeDistribution(trades: viewModel.trades)
        } right: {
            ConsistencyScore(trades: viewModel.trades)
        }
        equalHeightRow {
            EmotionalAnalytics(trades: viewModel.trades)
        } right: {
            ChecklistAnalytics(trades: viewModel.trades)
        }
        ImprovementTracker(trades: viewModel.trades)
        TradeComparison(trades: viewModel.trades)
        PlaybookCatalog(trades: viewModel.trades)
    }

    // MARK: - Advanced (deep dives)

    @ViewBuilder
    private var advancedContent: some View {
        CalendarCorrelation(trades: viewModel.trades)
        EventImpactProfiler(trades: viewModel.trades)
        equalHeightRow {
            BenchmarkComparison(trades: viewModel.trades, metrics: viewModel.metrics)
        } right: {
            SymbolCorrelation(trades: viewModel.trades)
        }
        DataQuality(trades: viewModel.trades)
        ShareableSummary(trades: viewModel.trades, metrics: viewModel.metrics)
        equalHeightRow {
            EdgeDecayMonitor(trades: viewModel.trades)
        } right: {
            TimeToMFEAnalysis(trades: viewModel.trades)
        }
        IntradayEquityCurve(trades: viewModel.trades)
        RegimeAnalysis(trades: viewModel.trades)
        EarningsImpact(trades: viewModel.trades)
        StrategyCheckpoints(
            trades: viewModel.trades,
            checkpoints: viewModel.checkpoints,
            onAdd: { viewModel.addCheckpoint($0) },
            onDelete: { viewModel.deleteCheckpoint(id: $0) }
        )
    }

    // MARK: - Prop Firm

    @ViewBuilder
    private var propFirmContent: some View {
        PropFirmTracker(trades: viewModel.trades)
    }

    // MARK: - Equal Height Row

    private func equalHeightRow<L: View, R: View>(
        @ViewBuilder left: () -> L,
        @ViewBuilder right: () -> R
    ) -> some View {
        EqualHeightHStack(spacing: 16) {
            StretchingCard { left() }
            StretchingCard { right() }
        }
    }

    // MARK: - Export

    private func exportDashboardPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Greenwick_Dashboard_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = PDFExporter()
        do {
            try exporter.exportDashboard(
                trades: viewModel.trades,
                metrics: viewModel.metrics,
                edgeBySession: viewModel.edgeBySession,
                edgeByHour: viewModel.edgeByHour,
                edgeBySymbol: viewModel.edgeBySymbol,
                edgeByDay: viewModel.edgeByDay,
                to: url
            )
            appState.showToast(.success, "Dashboard exported to PDF")
        } catch {
            appState.showToast(.error, "Export failed: \(error.localizedDescription)")
        }
    }

    private func exportDashboardCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Greenwick_Trades_\(Date().formatted(.dateTime.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = CSVExporter()
        do {
            try exporter.export(trades: viewModel.trades, to: url)
            appState.showToast(.success, "CSV exported with \(viewModel.trades.count) trades")
        } catch {
            appState.showToast(.error, "CSV export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Key Metrics Grid

    private var metricsGrid: some View {
        // Primary KPI row — Total P&L is visually dominant, others are secondary
        HStack(spacing: 12) {
            MetricCard(
                title: "Total P&L",
                value: viewModel.metrics.totalProfit.asCurrency,
                subtitle: "\(viewModel.metrics.totalTrades) trades",
                valueColor: Color.forPnL(viewModel.metrics.totalProfit),
                tooltip: "Net profit/loss across all filtered trades. Green = profitable, red = losing.",
                isHero: true
            )
            MetricCard(
                title: "Win Rate",
                value: viewModel.metrics.winRate.asPercent,
                subtitle: "\(viewModel.metrics.wins)W / \(viewModel.metrics.losses)L",
                valueColor: .semanticAmber,
                tooltip: "Percentage of trades that closed in profit. Above 50% is generally good, but depends on your R-multiple."
            )
            MetricCard(
                title: "Profit Factor",
                value: viewModel.metrics.profitFactor.asProfitFactor,
                subtitle: "Gross: \(viewModel.metrics.grossProfit.asCompactCurrency)",
                valueColor: .semanticBlue,
                tooltip: "Gross profit divided by gross loss. Above 1.5 is strong. Below 1.0 means you're losing money overall."
            )
            MetricCard(
                title: "Expectancy",
                value: viewModel.metrics.expectancy.asCurrency,
                subtitle: "per trade",
                valueColor: .semanticPurple,
                tooltip: "Expected dollar value per trade: (Win% x Avg Win) - (Loss% x Avg Loss). Positive = profitable edge."
            )
        }
    }

    // MARK: - Secondary Metrics (shown in Sessions category)

    private var secondaryMetricsRow: some View {
        HStack(spacing: 8) {
            MetricCardSmall(
                title: "Avg Win",
                value: viewModel.metrics.averageWin.asCurrency,
                valueColor: .semanticGreen,
                tooltip: "Average profit on winning trades."
            )
            MetricCardSmall(
                title: "Avg Loss",
                value: (-viewModel.metrics.averageLoss).asCurrency,
                valueColor: .semanticRed,
                tooltip: "Average loss on losing trades. Compare to Avg Win — ideally your wins are 1.5-2x larger."
            )
            MetricCardSmall(
                title: "Max DD",
                value: viewModel.metrics.maxDrawdown.asCurrency,
                valueColor: .semanticAmber,
                tooltip: "Maximum drawdown — the largest peak-to-trough decline in your equity curve."
            )
            MetricCardSmall(
                title: "Sharpe",
                value: String(format: "%.2f", viewModel.metrics.sharpeRatio),
                valueColor: .semanticBlue,
                tooltip: "Risk-adjusted return. Above 1.0 is good, above 2.0 is excellent. Measures consistency relative to volatility."
            )
            MetricCardSmall(
                title: "Avg R",
                value: viewModel.metrics.averageRMultiple.asRMultiple,
                valueColor: .semanticPurple,
                tooltip: "Average R-multiple per trade. R = profit as multiples of initial risk (stop distance). Above 0.5R is strong."
            )
        }
    }

    // MARK: - Equity Curve

    private var equityCurveChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equity Curve")
                .font(.cardTitle)

            if viewModel.equityCurve.isEmpty {
                emptyState("Import trades to see your equity curve")
            } else {
                Chart {
                    ForEach(Array(viewModel.equityCurve.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("P&L", point.cumulative)
                        )
                        .foregroundStyle(Color.forPnL(viewModel.metrics.totalProfit))

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("P&L", point.cumulative)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.forPnL(viewModel.metrics.totalProfit).opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                            }
                        }
                    }
                }
                .chartYAxisLabel("Cum. P&L", position: .leading)
                .frame(height: 250)
                .accessibilityLabel("Equity curve chart showing cumulative profit and loss over time. Current total: \(viewModel.metrics.totalProfit.asCurrency)")
                .accessibilityAddTraits(.isImage)
            }
        }
        .padding(16)
        .heroCard()
        .accentTopBar()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Edge Breakdowns

    private var edgeBreakdowns: some View {
        VStack(spacing: 16) {
            equalHeightRow {
                edgeCard(title: "P&L by Session", icon: "clock", accentColor: .semanticBlue, data: viewModel.edgeBySession)
            } right: {
                edgeCard(title: "P&L by Symbol", icon: "chart.bar", accentColor: .semanticPurple, data: viewModel.edgeBySymbol)
            }
            equalHeightRow {
                edgeCard(title: "P&L by Hour", icon: "gauge", accentColor: .semanticAmber, data: viewModel.edgeByHour.prefix(10).map { $0 })
            } right: {
                edgeCard(title: "P&L by Day", icon: "calendar", accentColor: .semanticCyan, data: viewModel.edgeByDay)
            }
        }
    }

    private func edgeCard(title: String, icon: String = "chart.bar", accentColor: Color = .accent, data: [MetricsCalculator.EdgeBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.cardTitle)
                .foregroundStyle(accentColor)

            if data.isEmpty {
                emptyState("No data yet")
            } else {
                ForEach(data) { item in
                    HStack {
                        Text(item.label)
                            .font(.smallText)
                            .frame(width: 70, alignment: .leading)
                        ProgressView(value: normalizedProfit(item.profit, in: data), total: 1.0)
                            .tint(Color.forPnL(item.profit))
                        Text(item.profit.asCurrency)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.forPnL(item.profit))
                            .frame(width: 70, alignment: .trailing)
                        Text("\(item.tradeCount)t")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 25, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
    }

    private func normalizedProfit(_ profit: Double, in data: [MetricsCalculator.EdgeBreakdown]) -> Double {
        let maxAbs = data.map { abs($0.profit) }.max() ?? 1
        guard maxAbs > 0 else { return 0 }
        return abs(profit) / maxAbs
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
