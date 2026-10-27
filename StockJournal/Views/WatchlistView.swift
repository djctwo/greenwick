import SwiftUI
import os

/// Watchlist view — track symbols and see aggregated trading stats per ticker
struct WatchlistView: View {
    let trades: [Trade]

    @State private var viewModel = WatchlistViewModel()
    @State private var newSymbol: String = ""
    @State private var isAddingSymbol: Bool = false
    @State private var stockService = StockDataService()
    @State private var quotes: [String: StockQuote] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.borderSubtle)

            if viewModel.symbols.isEmpty {
                emptyState
            } else {
                sortBar
                scrollContent
            }
        }
        .background(Color.bgContent)
        .onAppear {
            viewModel.computeStats(from: trades)
            Task { await fetchAllQuotes() }
        }
        .onChange(of: trades.count) {
            viewModel.computeStats(from: trades)
        }
        .onChange(of: viewModel.symbols.count) {
            Task { await fetchAllQuotes() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Watchlist")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("\(viewModel.symbols.count) symbols")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if isAddingSymbol {
                addSymbolField
            } else {
                Button {
                    isAddingSymbol = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.bodyText)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var addSymbolField: some View {
        HStack(spacing: 8) {
            TextField("Symbol", text: $newSymbol)
                .textFieldStyle(.roundedBorder)
                .font(.tableCell)
                .frame(width: 100)
                .onChange(of: newSymbol) { _, newValue in
                    newSymbol = newValue.uppercased()
                }
                .onSubmit { addSymbol() }

            Button {
                addSymbol()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
            .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                newSymbol = ""
                isAddingSymbol = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack {
            Spacer()
            Picker("Sort", selection: $viewModel.sortOrder) {
                Text("A-Z").tag(WatchlistSortOrder.alphabetical)
                Text("P&L").tag(WatchlistSortOrder.byPnL)
                Text("Trades").tag(WatchlistSortOrder.byTradeCount)
                Text("Win %").tag(WatchlistSortOrder.byWinRate)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.sortedSymbols, id: \.self) { symbol in
                    symbolCard(symbol)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removeSymbol(symbol)
                            } label: {
                                Label("Remove from Watchlist", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func symbolCard(_ symbol: String) -> some View {
        let stats = viewModel.statsMap[symbol]
        let quote = quotes[symbol]

        return HStack(spacing: 0) {
            // Color bar
            Rectangle()
                .fill(Color.forTicker(symbol))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                // Top row: symbol + price + P&L
                HStack(alignment: .firstTextBaseline) {
                    Text(symbol)
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)

                    if let stats, !stats.sector.isEmpty {
                        Text(stats.sector)
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    // Live price
                    if let quote {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", quote.currentPrice))
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.textPrimary)
                            Text(quote.formattedChange)
                                .font(.monoSmall)
                                .foregroundStyle(quote.isPositive ? Color.semanticGreen : Color.semanticRed)
                        }
                    }
                }

                // Bottom row: trading stats
                HStack(spacing: 16) {
                    if let stats, stats.tradeCount > 0 {
                        statLabel("\(stats.tradeCount) trades", icon: "list.bullet")
                        statLabel(String(format: "Win: %.0f%%", stats.winRate), icon: "chart.bar.fill")
                        statLabel(pnlText(stats.totalPnL), icon: "dollarsign.circle")
                    } else {
                        Text("No trading history")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(12)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.borderCard, lineWidth: 1)
        )
    }

    private func statLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.monoSmall)
            Text(text)
                .font(.monoSmall)
        }
        .foregroundStyle(Color.textSecondary)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "eye.fill")
                .font(.kpiValue)
                .foregroundStyle(Color.textTertiary)
            Text("No symbols on your watchlist")
                .font(.cardTitle)
                .foregroundStyle(Color.textSecondary)
            Text("Add symbols to track your trading performance per ticker.")
                .font(.bodyText)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button {
                isAddingSymbol = true
            } label: {
                Label("Add Symbol", systemImage: "plus")
                    .font(.bodyText)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quote Fetching

    private func fetchAllQuotes() async {
        guard stockService.hasAPIKey else { return }
        for symbol in viewModel.symbols {
            if quotes[symbol] == nil {
                do {
                    let quote = try await stockService.fetchQuote(symbol: symbol)
                    quotes[symbol] = quote
                } catch {
                    // Silently skip — will show "No price data" instead
                }
            }
        }
    }

    // MARK: - Helpers

    private func addSymbol() {
        let cleaned = newSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return }
        viewModel.addSymbol(cleaned)
        viewModel.computeStats(from: trades)
        newSymbol = ""
        isAddingSymbol = false
    }

    private func pnlText(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "$%.2f", value))"
    }
}

// MARK: - Sort Order

enum WatchlistSortOrder: String, CaseIterable, Sendable {
    case alphabetical
    case byPnL
    case byTradeCount
    case byWinRate
}

// MARK: - Symbol Stats

struct WatchlistSymbolStats: Sendable {
    let tradeCount: Int
    let winRate: Double      // 0-100
    let totalPnL: Double
    let avgPnL: Double
    let sector: String
}

// MARK: - View Model

@Observable
@MainActor
final class WatchlistViewModel {
    private static let logger = Logger(subsystem: "com.greenwick", category: "WatchlistViewModel")
    private static let storageKey = "watchlistSymbols"

    var symbols: [String] = []
    var statsMap: [String: WatchlistSymbolStats] = [:]
    var sortOrder: WatchlistSortOrder = .alphabetical

    init() {
        symbols = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(symbols, forKey: Self.storageKey)
    }

    func addSymbol(_ symbol: String) {
        guard !symbols.contains(symbol) else { return }
        symbols.append(symbol)
        save()
        Self.logger.info("Added \(symbol) to watchlist")
    }

    func removeSymbol(_ symbol: String) {
        symbols.removeAll { $0 == symbol }
        statsMap.removeValue(forKey: symbol)
        save()
        Self.logger.info("Removed \(symbol) from watchlist")
    }

    // MARK: - Stats Computation

    func computeStats(from trades: [Trade]) {
        var map: [String: WatchlistSymbolStats] = [:]

        for symbol in symbols {
            let symbolTrades = trades.filter { $0.symbol == symbol }

            if symbolTrades.isEmpty {
                map[symbol] = WatchlistSymbolStats(
                    tradeCount: 0,
                    winRate: 0,
                    totalPnL: 0,
                    avgPnL: 0,
                    sector: ""
                )
            } else {
                let count = symbolTrades.count
                let wins = symbolTrades.filter(\.isWin).count
                let winRate = Double(wins) / Double(count) * 100
                let totalPnL = symbolTrades.reduce(0.0) { $0 + $1.profitDouble }
                let avgPnL = totalPnL / Double(count)
                let sector = symbolTrades.first(where: { !$0.sector.isEmpty })?.sector ?? ""

                map[symbol] = WatchlistSymbolStats(
                    tradeCount: count,
                    winRate: winRate,
                    totalPnL: totalPnL,
                    avgPnL: avgPnL,
                    sector: sector
                )
            }
        }

        statsMap = map
    }

    // MARK: - Sorting

    var sortedSymbols: [String] {
        switch sortOrder {
        case .alphabetical:
            return symbols.sorted()
        case .byPnL:
            return symbols.sorted { (statsMap[$0]?.totalPnL ?? 0) > (statsMap[$1]?.totalPnL ?? 0) }
        case .byTradeCount:
            return symbols.sorted { (statsMap[$0]?.tradeCount ?? 0) > (statsMap[$1]?.tradeCount ?? 0) }
        case .byWinRate:
            return symbols.sorted { (statsMap[$0]?.winRate ?? 0) > (statsMap[$1]?.winRate ?? 0) }
        }
    }
}
