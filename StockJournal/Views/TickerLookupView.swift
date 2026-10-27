import SwiftUI
import os

/// Real-time stock ticker lookup with personal trading history.
///
/// Shows live market data from Finnhub alongside the user's own
/// trade stats for the selected symbol — the killer feature that
/// connects market data to personal performance.
struct TickerLookupView: View {
    let trades: [Trade]

    @State private var stockService = StockDataService()

    @State private var searchText = ""
    @State private var searchResults: [SymbolSearchResult] = []
    @State private var selectedSymbol: String?
    @State private var quote: StockQuote?
    @State private var profile: CompanyProfile?
    @State private var isSearching = false
    @State private var showSearchResults = false
    @State private var errorMessage: String?
    @State private var watchlistSymbols: Set<String> = []
    @State private var showWatchlistAdded = false

    private static let logger = Logger(subsystem: "com.greenwick", category: "TickerLookup")
    private static let watchlistKey = "watchlistSymbols"

    // MARK: - Debounce

    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchBar
                searchResultsDropdown

                if !stockService.hasAPIKey {
                    apiKeyPrompt
                } else if let symbol = selectedSymbol {
                    if stockService.isLoading && quote == nil {
                        loadingIndicator
                    } else {
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        if let quote, let profile {
                            quoteCard(quote: quote, profile: profile)
                            historySection(symbol: symbol)
                            recentTradesSection(symbol: symbol)
                        } else if let quote {
                            quoteCardMinimal(quote: quote, symbol: symbol)
                            historySection(symbol: symbol)
                            recentTradesSection(symbol: symbol)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .background(Color.bgContent)
        .onAppear {
            watchlistSymbols = Set(UserDefaults.standard.stringArray(forKey: Self.watchlistKey) ?? [])
        }
    }

    // MARK: - Watchlist Toggle

    private func isOnWatchlist(_ symbol: String) -> Bool {
        watchlistSymbols.contains(symbol.uppercased())
    }

    private func toggleWatchlist(_ symbol: String) {
        let upper = symbol.uppercased()
        var list = UserDefaults.standard.stringArray(forKey: Self.watchlistKey) ?? []
        if list.contains(upper) {
            list.removeAll { $0 == upper }
            watchlistSymbols.remove(upper)
        } else {
            list.append(upper)
            watchlistSymbols.insert(upper)
        }
        UserDefaults.standard.set(list, forKey: Self.watchlistKey)
    }

    private func watchlistButton(for symbol: String) -> some View {
        let onList = isOnWatchlist(symbol)
        return Button {
            toggleWatchlist(symbol)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: onList ? "eye.fill" : "eye")
                    .font(.smallText)
                Text(onList ? "Watching" : "Watch")
                    .font(.smallText)
            }
            .foregroundStyle(onList ? Color.accent : Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(onList ? Color.accent.opacity(0.15) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(onList ? Color.accent.opacity(0.3) : Color.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textSecondary)
                .font(.bodyText)

            TextField("Search ticker...", text: $searchText)
                .font(.bodyText)
                .foregroundStyle(Color.textPrimary)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, newValue in
                    debouncedSearch(query: newValue)
                }
                .onSubmit {
                    if !searchText.isEmpty {
                        selectSymbol(searchText.uppercased())
                    }
                }

            if !searchText.isEmpty {
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if let symbol = selectedSymbol {
                Text(symbol)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Search Results Dropdown

    @ViewBuilder
    private var searchResultsDropdown: some View {
        if showSearchResults && searchResults.isEmpty && !isSearching {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)
                Text("No results found")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        } else if showSearchResults && !searchResults.isEmpty {
            VStack(spacing: 0) {
                ForEach(searchResults) { result in
                    Button {
                        selectSymbol(result.symbol)
                    } label: {
                        HStack {
                            Text(result.displaySymbol)
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.accent)
                                .frame(width: 80, alignment: .leading)

                            Text(result.description)
                                .font(.smallText)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(result.type)
                                .font(.monoSmall)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if result.id != searchResults.last?.id {
                        Divider()
                            .background(Color.borderSubtle)
                    }
                }
            }
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        }
    }

    // MARK: - Quote Card (Full — with profile)

    private func quoteCard(quote: StockQuote, profile: CompanyProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: company name + symbol + watchlist
            HStack(alignment: .firstTextBaseline) {
                Text(profile.name.uppercased())
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                watchlistButton(for: profile.ticker)

                Text(profile.ticker)
                    .font(.kpiValueSecondary)
                    .foregroundStyle(Color.accent)
            }

            // Price + change
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(quote.formattedPrice)
                    .font(.kpiValue)
                    .foregroundStyle(Color.textPrimary)

                Text(quote.formattedChange)
                    .font(.monoSubtitle)
                    .foregroundStyle(quote.isPositive ? Color.semanticGreen : Color.semanticRed)
            }

            Divider().background(Color.borderSubtle)

            // OHLC grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                metricRow(label: "Open", value: formatPrice(quote.open))
                metricRow(label: "High", value: formatPrice(quote.high))
                metricRow(label: "Low", value: formatPrice(quote.low))
                metricRow(label: "Prev Close", value: formatPrice(quote.previousClose))
            }

            Divider().background(Color.borderSubtle)

            // Company details
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                metricRow(label: "Market Cap", value: profile.formattedMarketCap)
                metricRow(label: "Exchange", value: profile.exchange)
                metricRow(label: "Industry", value: profile.industry)
                metricRow(label: "Shares Out", value: profile.formattedShares)
                metricRow(label: "IPO", value: profile.ipo)
                metricRow(label: "Country", value: profile.country)
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Quote Card (Minimal — no profile)

    private func quoteCardMinimal(quote: StockQuote, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(symbol)
                    .font(.kpiValueSecondary)
                    .foregroundStyle(Color.accent)

                Spacer()

                watchlistButton(for: symbol)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(quote.formattedPrice)
                    .font(.kpiValue)
                    .foregroundStyle(Color.textPrimary)

                Text(quote.formattedChange)
                    .font(.monoSubtitle)
                    .foregroundStyle(quote.isPositive ? Color.semanticGreen : Color.semanticRed)
            }

            Divider().background(Color.borderSubtle)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                metricRow(label: "Open", value: formatPrice(quote.open))
                metricRow(label: "High", value: formatPrice(quote.high))
                metricRow(label: "Low", value: formatPrice(quote.low))
                metricRow(label: "Prev Close", value: formatPrice(quote.previousClose))
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Your History Section

    private func historySection(symbol: String) -> some View {
        let symbolTrades = trades.filter { $0.symbol.uppercased() == symbol.uppercased() }

        return Group {
            if symbolTrades.isEmpty {
                noHistoryCard(symbol: symbol)
            } else {
                historyCard(symbolTrades: symbolTrades, symbol: symbol)
            }
        }
    }

    private func historyCard(symbolTrades: [Trade], symbol: String) -> some View {
        let wins = symbolTrades.filter(\.isWin).count
        let total = symbolTrades.count
        let winRate = total > 0 ? Double(wins) / Double(total) * 100 : 0
        let totalPnL = symbolTrades.reduce(Decimal.zero) { $0 + $1.netProfit }
        let totalPnLDouble = NSDecimalNumber(decimal: totalPnL).doubleValue
        let avgPnL = total > 0 ? totalPnLDouble / Double(total) : 0
        let bestTrade = symbolTrades.max(by: { $0.profitDouble < $1.profitDouble })?.profitDouble ?? 0
        let worstTrade = symbolTrades.min(by: { $0.profitDouble < $1.profitDouble })?.profitDouble ?? 0
        let avgHold = symbolTrades.map(\.durationMin).overflowSafeAverage()
        let avgShares = total > 0 ? symbolTrades.reduce(0.0) { $0 + $1.shares } / Double(total) : 0

        // Best session by win rate
        let sessionStats = Dictionary(grouping: symbolTrades, by: \.session)
        let bestSession = sessionStats.max(by: { sessionA, sessionB in
            let wrA = Double(sessionA.value.filter(\.isWin).count) / max(Double(sessionA.value.count), 1)
            let wrB = Double(sessionB.value.filter(\.isWin).count) / max(Double(sessionB.value.count), 1)
            return wrA < wrB
        })

        // Most traded day of week
        let dayStats = TradingCalendar.groupedByWeekday(symbolTrades)
        let mostTradedDay = dayStats.max(by: { $0.value.count < $1.value.count })

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("YOUR HISTORY")

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                metricRow(
                    label: "Trades",
                    value: "\(total)",
                    valueColor: Color.textPrimary
                )
                metricRow(
                    label: "Win Rate",
                    value: String(format: "%.0f%%", winRate),
                    valueColor: winRate >= 50 ? Color.semanticGreen : Color.semanticRed
                )
                metricRow(
                    label: "Total P&L",
                    value: formatPnL(totalPnLDouble),
                    valueColor: Color.forPnL(totalPnLDouble)
                )
                metricRow(
                    label: "Avg P&L",
                    value: formatPnL(avgPnL),
                    valueColor: Color.forPnL(avgPnL)
                )
                metricRow(
                    label: "Best",
                    value: formatPnL(bestTrade),
                    valueColor: Color.semanticGreen
                )
                metricRow(
                    label: "Worst",
                    value: formatPnL(worstTrade),
                    valueColor: Color.semanticRed
                )
                metricRow(
                    label: "Avg Hold",
                    value: "\(avgHold) min"
                )
                metricRow(
                    label: "Avg Shares",
                    value: String(format: "%.0f", avgShares)
                )
            }

            if let bestSession {
                let sessionWR = Double(bestSession.value.filter(\.isWin).count) / Double(bestSession.value.count) * 100
                metricRow(
                    label: "Best Session",
                    value: "\(bestSession.key.displayName) (\(String(format: "%.0f%%", sessionWR)) WR)",
                    valueColor: Color.forSession(bestSession.key)
                )
            }

            if let mostTradedDay {
                metricRow(
                    label: "Most Traded",
                    value: "\(mostTradedDay.key)s (\(mostTradedDay.value.count) trades)"
                )
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    private func noHistoryCard(symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.text.clipboard")
                .font(.kpiValue)
                .foregroundStyle(Color.textTertiary)

            Text("No trading history for \(symbol)")
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)

            Text("Import trades or add manual entries to see your stats here.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Recent Trades Section

    private func recentTradesSection(symbol: String) -> some View {
        let symbolTrades = trades
            .filter { $0.symbol.uppercased() == symbol.uppercased() }
            .sorted { $0.closeTime > $1.closeTime }
            .prefix(10)

        return Group {
            if !symbolTrades.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("RECENT TRADES")

                    ForEach(Array(symbolTrades), id: \.ticket) { trade in
                        tradeRow(trade)

                        if trade.ticket != symbolTrades.last?.ticket {
                            Divider().background(Color.borderSubtle)
                        }
                    }
                }
                .padding(16)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.borderCard, lineWidth: 1)
                )
            }
        }
    }

    private func tradeRow(_ trade: Trade) -> some View {
        HStack(spacing: 12) {
            // Date
            Text(trade.closeTime, format: TradingCalendar.formatStyle.month(.abbreviated).day()) // trading day (ET)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 50, alignment: .leading)

            // Direction
            Text(trade.direction.rawValue)
                .font(.monoSmall)
                .foregroundStyle(trade.direction == .buy ? Color.semanticGreen : Color.semanticRed)
                .frame(width: 36, alignment: .leading)

            // Shares
            Text(String(format: "%.0f sh", trade.shares))
                .font(.monoSmall)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 52, alignment: .trailing)

            Spacer()

            // P&L
            Text(formatPnL(trade.profitDouble))
                .font(.monoSubtitle)
                .foregroundStyle(Color.forPnL(trade.profitDouble))

            // R-multiple
            Text(String(format: "%.1fR", trade.rMultiple))
                .font(.monoSmall)
                .foregroundStyle(Color.forPnL(trade.rMultiple))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - API Key Prompt

    private var apiKeyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.kpiValue)
                .foregroundStyle(Color.semanticAmber)

            Text("Finnhub API Key Required")
                .font(.cardTitle)
                .foregroundStyle(Color.textPrimary)

            Text("Get a free API key from finnhub.io to enable real-time stock data, company profiles, and ticker search.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Link(destination: URL(string: "https://finnhub.io/register")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Get Free API Key")
                }
                .font(.bodyText)
                .foregroundStyle(Color.accent)
            }

            Text("Then add your key in Settings > Market Data.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.kpiValue)
                .foregroundStyle(Color.textTertiary)

            Text("Search for a ticker")
                .font(.cardTitle)
                .foregroundStyle(Color.textSecondary)

            Text("Look up any stock symbol to see real-time data and your personal trading history.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Loading & Error

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            Text("Fetching data...")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.semanticAmber)

            Text(message)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            if let selectedSymbol {
                Button {
                    errorMessage = nil
                    selectSymbol(selectedSymbol)
                } label: {
                    Text("Retry")
                        .font(.smallText)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.semanticAmberDim)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Reusable Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Color.textSecondary)
            .tracking(1.2)
    }

    private func metricRow(
        label: String,
        value: String,
        valueColor: Color = .textPrimary
    ) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(valueColor)
        }
    }

    // MARK: - Formatting Helpers

    private func formatPrice(_ price: Double) -> String {
        String(format: "$%.2f", price)
    }

    private func formatPnL(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "%@$%.0f", sign, value)
    }

    // MARK: - Actions

    private func debouncedSearch(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            searchResults = []
            showSearchResults = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            do {
                let results = try await stockService.searchSymbols(query: query)
                guard !Task.isCancelled else { return }
                searchResults = results
                showSearchResults = true
            } catch {
                Self.logger.error("Search failed: \(error.localizedDescription)")
                searchResults = []
                showSearchResults = false
            }
        }
    }

    private func selectSymbol(_ symbol: String) {
        let uppercased = symbol.uppercased()
        selectedSymbol = uppercased
        searchText = ""
        searchResults = []
        showSearchResults = false
        errorMessage = nil

        Task {
            do {
                quote = try await stockService.fetchQuote(symbol: uppercased)
            } catch {
                Self.logger.error("Quote fetch failed for \(uppercased): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }

            do {
                profile = try await stockService.fetchProfile(symbol: uppercased)
            } catch {
                // Profile failure is non-fatal — quote-only view still works
                Self.logger.warning("Profile fetch failed for \(uppercased): \(error.localizedDescription)")
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        searchResults = []
        showSearchResults = false
        selectedSymbol = nil
        quote = nil
        profile = nil
        errorMessage = nil
    }
}
