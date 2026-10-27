import SwiftUI

struct JournalView: View {
    @Bindable var viewModel: JournalViewModel
    @Environment(\.appState) private var appState
    @State private var selectedTrade: Trade?
    @State private var showReplay: Bool = false
    @State private var showAddTrade: Bool = false
    @State private var sortOrder = [KeyPathComparator(\Trade.closeTime, order: .reverse)]
    @SceneStorage("journalColumnConfig") private var columnCustomization: TableColumnCustomization<Trade>

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filteredTrades.isEmpty && viewModel.searchText.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No Trades Yet",
                    message: "Import trades from your broker to see your trade journal.",
                    actionTitle: "Go to Import"
                ) {
                    appState.selectedTab = .importTrades
                }
            } else {
                toolbar
                performanceSummary
                Divider()
                tradeTable
            }
        }
        .navigationTitle("Trade Journal")
        .sheet(item: $selectedTrade) { trade in
            TradeDetailView(trade: trade)
        }
        .sheet(isPresented: $showReplay) {
            TradeReplayView(trades: viewModel.filteredTrades)
        }
        .sheet(isPresented: $showAddTrade) {
            AddTradeView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddTrade)) { _ in
            showAddTrade = true
        }
    }

    // MARK: - Filter Helpers

    private var activeFilterCount: Int {
        var count = 0
        if viewModel.selectedSymbolFilter != nil { count += 1 }
        if viewModel.selectedSessionFilter != nil { count += 1 }
        if viewModel.selectedDirectionFilter != nil { count += 1 }
        if viewModel.selectedDateRange != .all { count += 1 }
        if !viewModel.searchText.isEmpty { count += 1 }
        return count
    }

    private func clearAllFilters() {
        viewModel.selectedSymbolFilter = nil
        viewModel.selectedSessionFilter = nil
        viewModel.selectedDirectionFilter = nil
        viewModel.selectedDateRange = .all
        viewModel.searchText = ""
    }

    // MARK: - Sorted Trades

    private var sortedTrades: [Trade] {
        viewModel.filteredTrades.sorted(using: sortOrder)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Search trades...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.bgContent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .frame(maxWidth: 200)

            // Symbol filter
            Picker("Symbol", selection: $viewModel.selectedSymbolFilter) {
                Text("All Symbols").tag(nil as String?)
                ForEach(viewModel.uniqueSymbols, id: \.self) { symbol in
                    Text(symbol).tag(symbol as String?)
                }
            }
            .frame(width: 120)
            .tint(viewModel.selectedSymbolFilter != nil ? Color.accent : nil)

            // Session filter
            Picker("Session", selection: $viewModel.selectedSessionFilter) {
                Text("All Sessions").tag(nil as MarketSession?)
                ForEach(MarketSession.allCases) { session in
                    Text(session.displayName).tag(session as MarketSession?)
                }
            }
            .frame(width: 130)
            .tint(viewModel.selectedSessionFilter != nil ? Color.accent : nil)

            // Direction filter
            Picker("Direction", selection: $viewModel.selectedDirectionFilter) {
                Text("All Dirs").tag(nil as TradeDirection?)
                Text("BUY").tag(TradeDirection.buy as TradeDirection?)
                Text("SELL").tag(TradeDirection.sell as TradeDirection?)
            }
            .frame(width: 90)
            .tint(viewModel.selectedDirectionFilter != nil ? Color.accent : nil)

            // Date range
            Picker("Range", selection: $viewModel.selectedDateRange) {
                ForEach(JournalViewModel.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .frame(width: 120)
            .tint(viewModel.selectedDateRange != .all ? Color.accent : nil)

            // Active filter count badge
            if activeFilterCount > 0 {
                Button {
                    clearAllFilters()
                } label: {
                    HStack(spacing: 4) {
                        Text("\(activeFilterCount) filter\(activeFilterCount > 1 ? "s" : "")")
                            .font(.monoSmall)
                        Image(systemName: "xmark")
                            .font(.monoSmall)
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Clear all filters")
            }

            Spacer()

            // Stats
            Text("\(viewModel.filteredTrades.count) trades")
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)
            Text(viewModel.totalFilteredProfit.asCurrency)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
                .foregroundStyle(Color.forPnL(viewModel.totalFilteredProfit))

            Divider()
                .frame(height: 16)

            // Add Trade — primary action
            Button {
                showAddTrade = true
            } label: {
                Label("Add Trade", systemImage: "plus.circle")
                    .font(.smallText)
            }
            .accessibilityIdentifier("journal.addTrade")
            .help("Add Trade (⌘N)")

            // Actions menu — export + replay consolidated
            Menu {
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Divider()

                Button {
                    showReplay = true
                } label: {
                    Label("Replay Trades", systemImage: "play.circle")
                }
                .disabled(viewModel.filteredTrades.count < 2)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.smallText)
            }
            .accessibilityIdentifier("journal.actionsMenu")
            .help("Export & replay options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Performance Summary Strip

    private var performanceSummary: some View {
        let metrics = MetricsCalculator.calculate(from: viewModel.filteredTrades)
        return HStack(spacing: 20) {
            summaryItem("P&L", value: metrics.totalProfit.asCurrency, color: Color.forPnL(metrics.totalProfit))
            summaryItem("Win Rate", value: metrics.winRate.asPercent, color: metrics.winRate >= 50 ? .semanticGreen : .semanticRed)
            summaryItem("PF", value: metrics.profitFactor.asProfitFactor, color: metrics.profitFactor >= 1 ? .semanticGreen : .semanticRed)
            summaryItem("Expect.", value: metrics.expectancy.asCurrency, color: Color.forPnL(metrics.expectancy))
            summaryItem("Avg R", value: metrics.averageRMultiple.asRMultiple, color: Color.forPnL(metrics.averageRMultiple))
            if metrics.maxWinStreak > 0 {
                summaryItem("Streak", value: "\(metrics.currentStreak > 0 ? "+" : "")\(metrics.currentStreak)", color: Color.forPnL(Double(metrics.currentStreak)))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.bgContent.opacity(0.5))
    }

    private func summaryItem(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    // MARK: - Trade Table

    private var portfolioMetrics: MetricsCalculator.PortfolioMetrics {
        MetricsCalculator.calculate(from: viewModel.filteredTrades)
    }

    private var cumulativePnLMap: [Int64: Double] {
        var cum = 0.0
        var map: [Int64: Double] = [:]
        let chronological = viewModel.filteredTrades.sorted { $0.closeTime < $1.closeTime }
        for trade in chronological {
            cum += trade.profitDouble
            map[trade.ticket] = cum
        }
        return map
    }

    private var tradeTable: some View {
        let metrics = portfolioMetrics
        let cumMap = cumulativePnLMap
        return Table(sortedTrades, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Close (ET)", value: \.closeTime) { trade in
                Button {
                    selectedTrade = trade
                } label: {
                    Text(trade.closeTime.tradeDisplayString)
                        .font(.monoSubtitle)
                }
                .buttonStyle(.plain)
            }
            .width(min: 90, ideal: 100)
            .customizationID("closeTime")

            TableColumn("Symbol", value: \.symbol) { trade in
                TickerLabel(symbol: trade.symbol)
            }
            .width(min: 70, ideal: 80)
            .customizationID("symbol")

            TableColumn("Dir", value: \.direction) { trade in
                DirectionLabel(direction: trade.direction)
            }
            .width(min: 50, ideal: 55)
            .customizationID("direction")

            TableColumn("Shares", value: \.shares) { trade in
                Text(String(format: "%.2f", trade.shares))
                    .font(.monoSubtitle)
            }
            .width(min: 40, ideal: 55)
            .customizationID("shares")

            TableColumn("P&L", value: \.netProfit) { trade in
                Text(trade.profitDouble.asCurrency)
                    .font(.monoSubtitle)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.forPnL(trade.netProfit))
            }
            .width(min: 70, ideal: 80)
            .customizationID("pnl")

            TableColumn("Cum P&L") { trade in
                let cum = cumMap[trade.ticket] ?? 0
                Text(cum.asCompactCurrency)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(cum))
            }
            .width(min: 55, ideal: 65)
            .customizationID("cumPnl")

            TableColumn("R", value: \.rMultiple) { trade in
                Text(trade.rMultiple.asRMultiple)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(trade.rMultiple))
            }
            .width(min: 50, ideal: 55)
            .customizationID("rMultiple")

            TableColumn("Grade") { trade in
                let grade = TradeGrader.grade(trade, portfolioMetrics: metrics)
                GradeBadge(grade: grade)
            }
            .width(min: 35, ideal: 40)
            .customizationID("grade")

            TableColumn("Session", value: \.session) { trade in
                SessionBadge(session: trade.session)
            }
            .width(min: 75, ideal: 85)
            .customizationID("session")

            TableColumn("Hour", value: \.hour) { trade in
                Text("\(trade.hour):00")
                    .font(.monoSubtitle)
            }
            .width(min: 40, ideal: 45)
            .customizationID("hour")
        }
    }

    // MARK: - Export

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Greenwick_Journal_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let metrics = MetricsCalculator.calculate(from: viewModel.filteredTrades)
        let exporter = PDFExporter()
        do {
            try exporter.exportJournal(trades: viewModel.filteredTrades, metrics: metrics, to: url)
            appState.showToast(.success, "PDF exported with \(viewModel.filteredTrades.count) trades")
        } catch {
            appState.showToast(.error, "PDF export failed: \(error.localizedDescription)")
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Greenwick_Trades_\(Date().formatted(.dateTime.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = CSVExporter()
        do {
            try exporter.export(trades: viewModel.filteredTrades, to: url)
            appState.showToast(.success, "CSV exported with \(viewModel.filteredTrades.count) trades")
        } catch {
            appState.showToast(.error, "CSV export failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Identifiable Conformance for Pickers

extension MarketSession: Identifiable {
    public var id: String { rawValue }
}
