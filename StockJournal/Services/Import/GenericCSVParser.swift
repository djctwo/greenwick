import Foundation
import os

/// Parses CSV trade exports from any platform by auto-detecting format or using column mapping
struct GenericCSVParser: Sendable {
    private static let logger = Logger(subsystem: "com.greenwick", category: "GenericCSV")

    // MARK: - Platform Detection

    /// Known platform formats with their expected headers
    enum Platform: String, CaseIterable, Sendable {
        case interactiveBrokers = "Interactive Brokers"
        case thinkorswim = "Thinkorswim"
        case tradingView = "TradingView"
        case ninjaTrader = "NinjaTrader"
        case webull = "Webull"
        case robinhood = "Robinhood"
        case schwab = "Charles Schwab"
        case fidelity = "Fidelity"
        case etrade = "E*Trade"
        case tastytrade = "Tastytrade"
        case generic = "Generic CSV"

        /// Whether this platform exports raw transactions needing FIFO pairing
        var needsFIFOPairing: Bool {
            switch self {
            case .robinhood, .schwab, .fidelity, .etrade, .tastytrade: true
            default: false
            }
        }
    }

    /// Result of auto-detecting the CSV format
    struct DetectionResult: Sendable {
        let platform: Platform
        let headers: [String]
        let sampleRows: [[String]]
        let mapping: ColumnMapping?
    }

    /// Detect the platform format from a CSV file
    static func detect(fileAt path: String) throws -> DetectionResult {
        var content = try readFile(at: path)

        // Strip UTF-8 BOM if present (Fidelity)
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }

        let lines = splitLines(content)
        guard let headerLine = lines.first, !headerLine.isEmpty else {
            throw GenericParseError.emptyFile
        }

        let headers = parseCSVLine(headerLine)
        let sampleRows = lines.dropFirst().prefix(5).map { parseCSVLine($0) }
        let headerSet = Set(headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })

        // Try first line as header
        if let mapping = detectPlatform(headers: headers, headerSet: headerSet) {
            return DetectionResult(platform: mapping.platform, headers: headers, sampleRows: Array(sampleRows), mapping: mapping)
        }

        // Schwab/Fidelity: first line may be metadata — try second line as header
        if lines.count >= 2 {
            let altHeaders = parseCSVLine(lines[1])
            let altHeaderSet = Set(altHeaders.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
            if let mapping = detectPlatform(headers: altHeaders, headerSet: altHeaderSet) {
                let altSampleRows = lines.dropFirst(2).prefix(5).map { parseCSVLine($0) }
                return DetectionResult(platform: mapping.platform, headers: altHeaders, sampleRows: Array(altSampleRows), mapping: mapping)
            }
        }

        return DetectionResult(platform: .generic, headers: headers, sampleRows: Array(sampleRows), mapping: nil)
    }

    // MARK: - Platform-Specific Detection

    private static func detectPlatform(headers: [String], headerSet: Set<String>) -> ColumnMapping? {
        // Interactive Brokers
        if headerSet.contains("tradeid") && headerSet.contains("symbol") && headerSet.contains("quantity") && headerSet.contains("t. price") {
            return ibMapping(headers: headers)
        }

        // Thinkorswim
        if headerSet.contains("exec time") && headerSet.contains("side") && headerSet.contains("qty") && headerSet.contains("symbol") {
            return tosMapping(headers: headers)
        }

        // TradingView
        if headerSet.contains("trade #") && headerSet.contains("signal") && headerSet.contains("contracts") {
            return tradingViewMapping(headers: headers)
        }

        // NinjaTrader
        if headerSet.contains("trade #") && headerSet.contains("instrument") && headerSet.contains("market position") && headerSet.contains("entry price") {
            return ninjaTraderMapping(headers: headers)
        }

        // Webull
        if headerSet.contains("symbol") && headerSet.contains("filled qty") && headerSet.contains("avg price") {
            return webullMapping(headers: headers)
        }

        // Robinhood — "Trans Code" + "Instrument" + "Activity Date"
        if headerSet.contains("trans code") && headerSet.contains("instrument") && headerSet.contains("activity date") {
            return transactionPlatformMapping(.robinhood)
        }

        // Charles Schwab — "Action" + "Fees & Comm" + "Symbol"
        if headerSet.contains("action") && headerSet.contains("fees & comm") && headerSet.contains("symbol") {
            return transactionPlatformMapping(.schwab)
        }

        // Fidelity — "Run Date" + "Security Description" + "Action"
        if headerSet.contains("run date") && headerSet.contains("security description") && headerSet.contains("action") {
            return transactionPlatformMapping(.fidelity)
        }

        // E*Trade — "TransactionType" or "Transaction Type" + "SecurityType"
        if (headerSet.contains("transactiontype") || headerSet.contains("transaction type"))
            && (headerSet.contains("securitytype") || headerSet.contains("security type")) {
            return transactionPlatformMapping(.etrade)
        }

        // Tastytrade — "Action" column with underscore values + "Underlying Symbol" or specific headers
        if (headerSet.contains("underlying symbol") || headerSet.contains("root symbol"))
            && (headerSet.contains("commissions") || headerSet.contains("clearing fees")) {
            return transactionPlatformMapping(.tastytrade)
        }

        return nil
    }

    /// Stub mapping for transaction-based platforms (detection only — actual parsing uses parseTransactions)
    private static func transactionPlatformMapping(_ platform: Platform) -> ColumnMapping {
        ColumnMapping(
            platform: platform, ticket: nil, symbol: 0, direction: 0, shares: 0,
            openTime: 0, closeTime: nil, openPrice: 0, closePrice: nil,
            sl: nil, tp: nil, profit: 0, commission: nil, swap: nil,
            maePoints: nil, mfePoints: nil, volume: nil, dateFormat: ""
        )
    }

    // MARK: - Parse with Mapping

    /// Parse a CSV file using a column mapping (auto-detected or user-provided)
    static func parse(fileAt path: String, mapping: ColumnMapping) throws -> [Trade] {
        // Route transaction-based platforms through FIFO pairing
        if mapping.platform.needsFIFOPairing {
            return try parseTransactions(fileAt: path, platform: mapping.platform)
        }

        let content = try readFile(at: path)
        let lines = splitLines(content)
        guard lines.count > 1 else {
            throw GenericParseError.emptyFile
        }

        let headers = parseCSVLine(lines[0])
        let now = Date()
        var trades: [Trade] = []
        var ticketKeys = TicketKeyCounter()

        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 4 else { continue }

            // Stable ID from the row's content: re-importing the same file skips
            // trades already in the journal, and different files never collide.
            let ticket = ticketKeys.ticket(for: "\(mapping.platform.rawValue)|\(fields.joined(separator: "|"))")

            do {
                let trade = try mapToTrade(fields: fields, headers: headers, mapping: mapping, lineNumber: i + 1, importedAt: now, ticket: ticket)
                trades.append(trade)
            } catch {
                logger.warning("Skipping line \(i + 1): \(error.localizedDescription)")
            }
        }

        logger.info("Parsed \(trades.count) trades from \(mapping.platform.rawValue) CSV")
        return trades
    }

    // MARK: - FIFO Transaction Pairing

    /// A raw transaction from a broker CSV (one Buy or Sell row)
    struct RawTransaction {
        let symbol: String
        let isBuy: Bool
        let shares: Double
        let price: Decimal
        let date: Date
        let commission: Decimal
        let fees: Decimal
    }

    /// Pair raw Buy/Sell transactions into matched trades using FIFO ordering.
    /// Handles partial fills: 100 shares bought, 50 sold → one trade for 50 shares, 50 remain in queue.
    static func pairTransactions(_ transactions: [RawTransaction], importedAt: Date, platform: Platform = .generic) -> [Trade] {
        // Group by symbol, then sort each group by date
        var bySymbol: [String: [RawTransaction]] = [:]
        for txn in transactions {
            bySymbol[txn.symbol, default: []].append(txn)
        }

        var trades: [Trade] = []
        var ticketKeys = TicketKeyCounter()

        for (symbol, txns) in bySymbol.sorted(by: { $0.key < $1.key }) {
            let sorted = txns.sorted { $0.date < $1.date }
            // FIFO queues: buys and sells with remaining shares
            var buyQueue: [(txn: RawTransaction, remaining: Double)] = []
            var sellQueue: [(txn: RawTransaction, remaining: Double)] = []

            for txn in sorted {
                if txn.isBuy {
                    buyQueue.append((txn, txn.shares))
                } else {
                    sellQueue.append((txn, txn.shares))
                }

                // Try to match buys against sells
                while !buyQueue.isEmpty && !sellQueue.isEmpty {
                    let matchShares = min(buyQueue[0].remaining, sellQueue[0].remaining)
                    guard matchShares > 0 else { break }

                    let buy = buyQueue[0].txn
                    let sell = sellQueue[0].txn

                    let pnl = (sell.price - buy.price) * Decimal(matchShares)
                    // Each side's costs are allocated by the share of THAT order being matched
                    let commPortion = (buy.commission + buy.fees) * Decimal(matchShares / buy.shares)
                        + (sell.commission + sell.fees) * Decimal(matchShares / sell.shares)

                    // Each input is bounded, but their product is not: refuse a pair whose
                    // P&L would exceed the documented maximum (it would only be a crafted file)
                    let netPnL = pnl - commPortion
                    guard abs(netPnL) <= maxAbsAmount, abs(commPortion) <= maxAbsAmount, !netPnL.isNaN else {
                        logger.warning("FIFO: skipped a \(symbol) pair with an out-of-range P&L")
                        buyQueue[0].remaining -= matchShares
                        sellQueue[0].remaining -= matchShares
                        if buyQueue[0].remaining <= 0.0001 { buyQueue.removeFirst() }
                        if sellQueue[0].remaining <= 0.0001 { sellQueue.removeFirst() }
                        continue
                    }

                    let ticket = ticketKeys.ticket(for: [
                        platform.rawValue, symbol,
                        "\(buy.date.timeIntervalSince1970)", "\(buy.price)", "\(buy.shares)",
                        "\(sell.date.timeIntervalSince1970)", "\(sell.price)", "\(sell.shares)",
                        "\(matchShares)",
                    ].joined(separator: "|"))

                    // A sale before the matching buy is a short: it opens with the sale
                    let isShort = sell.date < buy.date
                    let openTime = isShort ? sell.date : buy.date
                    let closeTime = isShort ? buy.date : sell.date
                    let duration = Int(saturating: closeTime.timeIntervalSince(openTime) / 60)
                    let session = openTime.marketSession
                    let dayOfWeek = openTime.shortDayName

                    trades.append(Trade(
                        id: nil,
                        ticket: ticket,
                        symbol: symbol,
                        direction: isShort ? .sell : .buy,
                        shares: matchShares,
                        openTime: openTime,
                        closeTime: closeTime,
                        durationMin: max(0, duration),
                        openPrice: isShort ? sell.price : buy.price,
                        closePrice: isShort ? buy.price : sell.price,
                        sl: 0,
                        tp: 0,
                        netProfit: netPnL, // net of this pair's share of costs
                        maePoints: 0,
                        mfePoints: 0,
                        rMultiple: 0,
                        session: session,
                        dayOfWeek: dayOfWeek,
                        hour: openTime.etHour,
                        rangeSize: 0,
                        hitBreakeven: false,
                        scaledIn: false,
                        comment: "",
                        timeToMFEMin: 0,
                        slDistPoints: 0,
                        slippagePoints: 0,
                        volume: 0,
                        commission: commPortion,
                        swap: 0,
                        importedAt: importedAt
                    ))

                    buyQueue[0].remaining -= matchShares
                    sellQueue[0].remaining -= matchShares
                    if buyQueue[0].remaining <= 0.0001 { buyQueue.removeFirst() }
                    if sellQueue[0].remaining <= 0.0001 { sellQueue.removeFirst() }
                }
            }

            if !buyQueue.isEmpty {
                logger.info("FIFO: \(buyQueue.count) unmatched buy(s) for \(symbol) (open position)")
            }
        }

        return trades.sorted { $0.openTime < $1.openTime }
    }

    // MARK: - Transaction-Based Parsing (Robinhood, Schwab, Fidelity, E*Trade, Tastytrade)

    /// Parse a CSV file that contains raw transactions (not matched trades) and pair them via FIFO
    static func parseTransactions(fileAt path: String, platform: Platform) throws -> [Trade] {
        var content = try readFile(at: path)

        // Strip UTF-8 BOM if present (Fidelity)
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }

        let allLines = splitLines(content)
        guard !allLines.isEmpty else { throw GenericParseError.emptyFile }

        // Preprocess: skip metadata headers/footers depending on platform
        let (headerLine, dataLines) = preprocessLines(allLines, platform: platform)
        let headers = parseCSVLine(headerLine)
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        var transactions: [RawTransaction] = []

        for line in dataLines {
            let fields = parseCSVLine(line)
            guard fields.count >= 4 else { continue }

            if let txn = parseTransaction(fields: fields, headerMap: h, platform: platform) {
                transactions.append(txn)
            }
        }

        let now = Date()
        let trades = pairTransactions(transactions, importedAt: now, platform: platform)
        logger.info("Parsed \(transactions.count) transactions → \(trades.count) paired trades from \(platform.rawValue)")
        return trades
    }

    /// Skip metadata headers/footers for specific platforms
    private static func preprocessLines(_ lines: [String], platform: Platform) -> (header: String, data: [String]) {
        switch platform {
        case .schwab:
            // First line is metadata ("Transactions for account..."), last line is "Transactions Total"
            guard lines.count >= 3 else { return (lines.first ?? "", []) }
            let dataLines = lines.dropFirst().dropLast().filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("Transactions Total") && !trimmed.isEmpty
            }
            return (lines[1], Array(dataLines.dropFirst()))

        case .fidelity:
            // Skip "Brokerage" pre-header and footer disclaimer lines
            var headerIdx = 0
            for (i, line) in lines.enumerated() {
                let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
                if lower.contains("run date") && lower.contains("action") && lower.contains("symbol") {
                    headerIdx = i
                    break
                }
            }
            let afterHeader = Array(lines.dropFirst(headerIdx + 1))
            let dataLines = afterHeader.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Skip footer disclaimer lines and empty lines
                return !trimmed.isEmpty
                    && !trimmed.hasPrefix("The data and information")
                    && !trimmed.hasPrefix("Fidelity")
                    && !trimmed.hasPrefix("\"The data")
                    && !trimmed.hasPrefix("\"Fidelity")
            }
            return (lines[headerIdx], dataLines)

        default:
            // Robinhood, E*Trade, Tastytrade: header is normally the first line, but some
            // exports put a title line above it — use the first line that looks like the header.
            let headerIdx = lines.prefix(10).firstIndex { line in
                let fields = parseCSVLine(line)
                let set = Set(fields.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
                return detectPlatform(headers: fields, headerSet: set)?.platform == platform
            } ?? 0
            return (lines[headerIdx], Array(lines.dropFirst(headerIdx + 1)))
        }
    }

    /// Parse a single transaction row into a RawTransaction
    private static func parseTransaction(fields: [String], headerMap: [String], platform: Platform) -> RawTransaction? {
        switch platform {
        case .robinhood:
            return parseRobinhoodTransaction(fields: fields, h: headerMap)
        case .schwab:
            return parseSchwabTransaction(fields: fields, h: headerMap)
        case .fidelity:
            return parseFidelityTransaction(fields: fields, h: headerMap)
        case .etrade:
            return parseETradeTransaction(fields: fields, h: headerMap)
        case .tastytrade:
            return parseTastytradeTransaction(fields: fields, h: headerMap)
        default:
            return nil
        }
    }

    // MARK: - Robinhood Transaction Parsing

    private static func parseRobinhoodTransaction(fields: [String], h: [String]) -> RawTransaction? {
        guard let transCodeIdx = h.firstIndex(of: "trans code"),
              let symbolIdx = h.firstIndex(of: "instrument"),
              let qtyIdx = h.firstIndex(of: "quantity"),
              let priceIdx = h.firstIndex(of: "price"),
              let dateIdx = h.firstIndex(of: "activity date") else { return nil }

        let transCode = (fields[safe: transCodeIdx] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        // Only trade transactions
        let buyTypes = ["BUY", "BTO"]
        let sellTypes = ["SELL", "STC"]
        guard buyTypes.contains(transCode) || sellTypes.contains(transCode) else { return nil }

        let symbol = cleanSymbol(fields[safe: symbolIdx] ?? "")
        guard !symbol.isEmpty else { return nil }

        guard let shares = parseShares(fields[safe: qtyIdx] ?? "") else { return nil }

        let priceStr = stripCurrencyChars(fields[safe: priceIdx] ?? "0")
        guard let price = parseDecimal(priceStr), price > 0 else { return nil }

        let dateStr = fields[safe: dateIdx] ?? ""
        guard let date = parseDateTime(dateStr, format: "M/d/yyyy") else { return nil }

        return RawTransaction(
            symbol: symbol, isBuy: buyTypes.contains(transCode),
            shares: shares, price: price, date: date, commission: 0, fees: 0
        )
    }

    // MARK: - Schwab Transaction Parsing

    private static func parseSchwabTransaction(fields: [String], h: [String]) -> RawTransaction? {
        guard let actionIdx = h.firstIndex(of: "action"),
              let symbolIdx = h.firstIndex(of: "symbol"),
              let qtyIdx = h.firstIndex(of: "quantity"),
              let priceIdx = h.firstIndex(of: "price"),
              let dateIdx = h.firstIndex(of: "date") else { return nil }

        let action = (fields[safe: actionIdx] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let buyActions = ["BUY", "BUY TO OPEN", "BUY TO COVER"]
        let sellActions = ["SELL", "SELL TO CLOSE", "SELL SHORT"]
        guard buyActions.contains(action) || sellActions.contains(action) else { return nil }

        let symbol = cleanSymbol(fields[safe: symbolIdx] ?? "")
        guard !symbol.isEmpty else { return nil }

        let qtyStr = (fields[safe: qtyIdx] ?? "0").replacingOccurrences(of: ",", with: "")
        guard let shares = parseShares(qtyStr) else { return nil }

        let priceStr = stripCurrencyChars(fields[safe: priceIdx] ?? "0")
        guard let price = parseDecimal(priceStr), price > 0 else { return nil }

        let dateStr = fields[safe: dateIdx] ?? ""
        guard let date = parseDateTime(dateStr, format: "MM/dd/yyyy") else { return nil }

        // Fees
        let feesIdx = h.firstIndex(of: "fees & comm")
        let feesStr = stripCurrencyChars(fields[safe: feesIdx ?? 999] ?? "0")
        let fees = parseDecimal(feesStr) ?? 0

        return RawTransaction(
            symbol: symbol, isBuy: buyActions.contains(action),
            shares: shares, price: price, date: date, commission: abs(fees), fees: 0
        )
    }

    // MARK: - Fidelity Transaction Parsing

    private static func parseFidelityTransaction(fields: [String], h: [String]) -> RawTransaction? {
        guard let actionIdx = h.firstIndex(of: "action"),
              let symbolIdx = h.firstIndex(of: "symbol"),
              let qtyIdx = h.firstIndex(of: "quantity"),
              let dateIdx = h.firstIndex(of: "run date") else { return nil }

        let action = (fields[safe: actionIdx] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let isBuy = action.contains("BOUGHT") || action.contains("BUY")
        let isSell = action.contains("SOLD") || action.contains("SELL")
        guard isBuy || isSell else { return nil }

        let symbol = cleanSymbol(fields[safe: symbolIdx] ?? "")
        guard !symbol.isEmpty else { return nil }

        let qtyStr = (fields[safe: qtyIdx] ?? "0").replacingOccurrences(of: ",", with: "")
        guard let shares = parseShares(qtyStr) else { return nil }

        // Fidelity header: "Price ($)" — find by partial match
        let priceIdx = h.firstIndex(where: { $0.contains("price") }) ?? 0
        let priceStr = stripCurrencyChars(fields[safe: priceIdx] ?? "0")
        guard let price = parseDecimal(priceStr), price > 0 else { return nil }

        let dateStr = fields[safe: dateIdx] ?? ""
        guard let date = parseDateTime(dateStr, format: "MM/dd/yyyy") else { return nil }

        // Commission and fees columns
        let commIdx = h.firstIndex(where: { $0.contains("commission") })
        let feesIdx = h.firstIndex(where: { $0.contains("fees") && !$0.contains("commission") })
        let comm = parseDecimal(stripCurrencyChars(fields[safe: commIdx ?? 999] ?? "0")) ?? 0
        let fees = parseDecimal(stripCurrencyChars(fields[safe: feesIdx ?? 999] ?? "0")) ?? 0

        return RawTransaction(
            symbol: symbol, isBuy: isBuy,
            shares: shares, price: price, date: date, commission: abs(comm), fees: abs(fees)
        )
    }

    // MARK: - E*Trade Transaction Parsing

    private static func parseETradeTransaction(fields: [String], h: [String]) -> RawTransaction? {
        // Support both website and Power E*Trade formats
        let dateIdx = h.firstIndex(of: "transactiondate") ?? h.firstIndex(of: "transaction date")
            ?? h.firstIndex(of: "date") ?? h.firstIndex(of: "execution date")
        let typeIdx = h.firstIndex(of: "transactiontype") ?? h.firstIndex(of: "transaction type")
            ?? h.firstIndex(of: "action") ?? h.firstIndex(of: "side")
        let symbolIdx = h.firstIndex(of: "symbol")
        let qtyIdx = h.firstIndex(of: "quantity") ?? h.firstIndex(of: "qty")
        let priceIdx = h.firstIndex(of: "price") ?? h.firstIndex(of: "execution price")

        guard let dIdx = dateIdx, let tIdx = typeIdx, let sIdx = symbolIdx,
              let quIdx = qtyIdx, let pIdx = priceIdx else { return nil }

        let action = (fields[safe: tIdx] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let buyActions = ["BOUGHT", "BUY", "BOUGHT TO OPEN", "BUY TO OPEN", "BUY TO COVER"]
        let sellActions = ["SOLD", "SELL", "SOLD TO CLOSE", "SELL TO CLOSE", "SELL SHORT"]
        let isBuy = buyActions.contains(action)
        let isSell = sellActions.contains(action)
        guard isBuy || isSell else { return nil }

        let symbol = cleanSymbol(fields[safe: sIdx] ?? "")
        guard !symbol.isEmpty else { return nil }

        let qtyStr = (fields[safe: quIdx] ?? "0").replacingOccurrences(of: ",", with: "")
        guard let shares = parseShares(qtyStr) else { return nil }

        let priceStr = stripCurrencyChars(fields[safe: pIdx] ?? "0")
        guard let price = parseDecimal(priceStr), price > 0 else { return nil }

        let dateStr = fields[safe: dIdx] ?? ""
        // E*Trade uses MM/DD/YY (2-digit year)
        guard let date = parseDateTime(dateStr, format: "MM/dd/yy") else { return nil }

        let commIdx = h.firstIndex(of: "commission") ?? h.firstIndex(of: "comm")
        let comm = parseDecimal(stripCurrencyChars(fields[safe: commIdx ?? 999] ?? "0")) ?? 0

        return RawTransaction(
            symbol: symbol, isBuy: isBuy,
            shares: shares, price: price, date: date, commission: abs(comm), fees: 0
        )
    }

    // MARK: - Tastytrade Transaction Parsing

    private static func parseTastytradeTransaction(fields: [String], h: [String]) -> RawTransaction? {
        let dateIdx = h.firstIndex(of: "date") ?? h.firstIndex(of: "executed at") ?? h.firstIndex(of: "exec date")
        let actionIdx = h.firstIndex(of: "action") ?? h.firstIndex(of: "type")
        let symbolIdx = h.firstIndex(of: "symbol") ?? h.firstIndex(of: "underlying symbol")
        let qtyIdx = h.firstIndex(of: "quantity") ?? h.firstIndex(of: "qty")
        let priceIdx = h.firstIndex(of: "price") ?? h.firstIndex(of: "average price")

        guard let dIdx = dateIdx, let aIdx = actionIdx, let sIdx = symbolIdx,
              let quIdx = qtyIdx, let pIdx = priceIdx else { return nil }

        let action = (fields[safe: aIdx] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let buyActions = ["BUY_TO_OPEN", "BUY", "BTO", "BUY_TO_CLOSE"]
        let sellActions = ["SELL_TO_CLOSE", "SELL", "STC", "SELL_TO_OPEN"]
        let isBuy = buyActions.contains(action)
        let isSell = sellActions.contains(action)
        guard isBuy || isSell else { return nil }

        let symbol = cleanSymbol(fields[safe: sIdx] ?? "")
        guard !symbol.isEmpty else { return nil }

        let qtyStr = (fields[safe: quIdx] ?? "0").replacingOccurrences(of: ",", with: "")
        guard let shares = parseShares(qtyStr) else { return nil }

        let priceStr = stripCurrencyChars(fields[safe: pIdx] ?? "0")
        guard let price = parseDecimal(priceStr), price > 0 else { return nil }

        // Tastytrade uses ISO 8601 dates with timestamps
        let dateStr = fields[safe: dIdx] ?? ""
        guard let date = parseDateTime(dateStr, format: "yyyy-MM-dd'T'HH:mm:ssZ") else { return nil }

        let commIdx = h.firstIndex(of: "commissions") ?? h.firstIndex(of: "commission")
        let feesIdx = h.firstIndex(of: "fees") ?? h.firstIndex(of: "clearing fees")
        let comm = parseDecimal(stripCurrencyChars(fields[safe: commIdx ?? 999] ?? "0")) ?? 0
        let fees = parseDecimal(stripCurrencyChars(fields[safe: feesIdx ?? 999] ?? "0")) ?? 0

        return RawTransaction(
            symbol: symbol, isBuy: isBuy,
            shares: shares, price: price, date: date, commission: abs(comm), fees: abs(fees)
        )
    }

    // MARK: - Field Mapping

    /// Maps CSV column indices to Trade fields
    struct ColumnMapping: Sendable {
        let platform: Platform
        let ticket: Int?
        let symbol: Int
        let direction: Int
        let shares: Int
        let openTime: Int
        let closeTime: Int?
        let openPrice: Int
        let closePrice: Int?
        let sl: Int?
        let tp: Int?
        let profit: Int
        let commission: Int?
        let swap: Int?
        let maePoints: Int?
        let mfePoints: Int?
        let volume: Int?
        let dateFormat: String

        var buyValues: [String] { ["BUY", "LONG", "BOT", "B"] }
        var sellValues: [String] { ["SELL", "SHORT", "SLD", "S"] }
    }

    // MARK: - Trade Construction

    private static func mapToTrade(
        fields: [String],
        headers: [String],
        mapping: ColumnMapping,
        lineNumber: Int,
        importedAt: Date,
        ticket: Int64
    ) throws -> Trade {
        // Symbol
        let symbol = cleanSymbol(fields[safe: mapping.symbol] ?? "")
        guard !symbol.isEmpty else {
            throw GenericParseError.missingField("symbol", lineNumber)
        }

        // Direction (sanitize to prevent formula injection if re-exported)
        let dirStr = sanitizeImportField(
            (fields[safe: mapping.direction] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        )
        let direction: TradeDirection
        if mapping.buyValues.contains(dirStr) || dirStr.contains("BUY") || dirStr.contains("LONG") || dirStr.contains("BOT") {
            direction = .buy
        } else if mapping.sellValues.contains(dirStr) || dirStr.contains("SELL") || dirStr.contains("SHORT") || dirStr.contains("SLD") {
            direction = .sell
        } else {
            if let qty = Double(dirStr), qty < 0 {
                direction = .sell
            } else {
                throw GenericParseError.invalidDirection(dirStr, lineNumber)
            }
        }

        // Shares
        guard let shares = parseShares(fields[safe: mapping.shares] ?? "") else {
            throw GenericParseError.missingField("shares (must be > 0)", lineNumber)
        }

        // Times
        let openTimeStr = fields[safe: mapping.openTime] ?? ""
        guard let openTime = parseDateTime(openTimeStr, format: mapping.dateFormat) else {
            throw GenericParseError.invalidDate(openTimeStr, lineNumber)
        }

        let closeTime: Date
        if let closeIdx = mapping.closeTime, let closeStr = fields[safe: closeIdx],
           let parsed = parseDateTime(closeStr, format: mapping.dateFormat) {
            closeTime = parsed
        } else {
            closeTime = openTime
        }

        // Prices
        let openPrice = parseDecimal(fields[safe: mapping.openPrice]) ?? 0
        let closePrice = mapping.closePrice.flatMap { parseDecimal(fields[safe: $0]) } ?? openPrice

        // P&L
        let profit = parseDecimal(fields[safe: mapping.profit]) ?? 0

        // Commission and swap. Brokers write commissions as positive or negative numbers;
        // either way it is a cost. Stored P&L is NET of costs (commission and swap are kept
        // separately for the cost analytics), so every statistic is after costs.
        let commissionValue = abs(mapping.commission.flatMap { parseDecimal(fields[safe: $0]) } ?? 0)
        let swapValue = mapping.swap.flatMap { parseDecimal(fields[safe: $0]) } ?? 0
        let netProfit = profit - commissionValue - swapValue // swap > 0 is a cost, as in Trade.totalCosts
        guard abs(netProfit) <= maxAbsAmount else {
            throw GenericParseError.missingField("P&L (out of range)", lineNumber)
        }

        // Optional fields
        let sl = mapping.sl.flatMap { parseDecimal(fields[safe: $0]) } ?? 0
        let tp = mapping.tp.flatMap { parseDecimal(fields[safe: $0]) } ?? 0
        let mae = mapping.maePoints.flatMap { parseBoundedDouble(fields[safe: $0]) } ?? 0
        let mfe = mapping.mfePoints.flatMap { parseBoundedDouble(fields[safe: $0]) } ?? 0
        let vol = mapping.volume.flatMap { fields[safe: $0] }.flatMap { Int($0) }.map { max(0, $0) } ?? 0

        // Derived fields
        let duration = Int(saturating: closeTime.timeIntervalSince(openTime) / 60)
        let session = openTime.marketSession
        let dayOfWeek = openTime.shortDayName
        let hour = openTime.etHour

        // Calculate SL distance and R-multiple
        let slDist: Double
        let rMult: Double
        if sl != 0 && openPrice != 0 {
            let slDistDecimal = abs(openPrice - sl)
            slDist = NSDecimalNumber(decimal: slDistDecimal).doubleValue
            rMult = slDist > 0 ? NSDecimalNumber(decimal: netProfit).doubleValue / (slDist * shares) : 0
        } else {
            slDist = 0
            rMult = 0
        }

        return Trade(
            id: nil,
            ticket: ticket,
            symbol: symbol,
            direction: direction,
            shares: shares,
            openTime: openTime,
            closeTime: closeTime,
            durationMin: max(0, duration),
            openPrice: openPrice,
            closePrice: closePrice,
            sl: sl,
            tp: tp,
            netProfit: netProfit,
            maePoints: mae,
            mfePoints: mfe,
            rMultiple: rMult,
            session: session,
            dayOfWeek: dayOfWeek,
            hour: hour,
            rangeSize: 0,
            hitBreakeven: false,
            scaledIn: false,
            comment: "",
            timeToMFEMin: 0,
            slDistPoints: slDist,
            slippagePoints: 0,
            volume: vol,
            commission: commissionValue,
            swap: swapValue,
            importedAt: importedAt
        )
    }

    // MARK: - Platform Mappings

    private static func ibMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .interactiveBrokers,
            ticket: h.firstIndex(of: "tradeid"),
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "side") ?? h.firstIndex(of: "buy/sell") ?? 0,
            shares: h.firstIndex(of: "quantity") ?? h.firstIndex(of: "shares") ?? 0,
            openTime: h.firstIndex(of: "date/time") ?? h.firstIndex(of: "tradetime") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "t. price") ?? h.firstIndex(of: "tradeprice") ?? 0,
            closePrice: h.firstIndex(of: "c. price") ?? h.firstIndex(of: "closeprice"),
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "realized p/l") ?? h.firstIndex(of: "mtm p/l") ?? h.firstIndex(of: "proceeds") ?? 0,
            commission: h.firstIndex(of: "comm/fee") ?? h.firstIndex(of: "commission"),
            swap: nil,
            maePoints: nil,
            mfePoints: nil,
            volume: nil,
            dateFormat: "yyyy-MM-dd, HH:mm:ss"
        )
    }

    private static func tosMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .thinkorswim,
            ticket: nil,
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "side") ?? 0,
            shares: h.firstIndex(of: "qty") ?? h.firstIndex(of: "amount") ?? 0,
            openTime: h.firstIndex(of: "exec time") ?? h.firstIndex(of: "date") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "price") ?? h.firstIndex(of: "net price") ?? 0,
            closePrice: nil,
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "p/l") ?? h.firstIndex(of: "net cash") ?? 0,
            commission: h.firstIndex(of: "commission") ?? h.firstIndex(of: "commissions"),
            swap: nil,
            maePoints: nil,
            mfePoints: nil,
            volume: nil,
            dateFormat: "MM/dd/yy HH:mm:ss"
        )
    }

    private static func tradingViewMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .tradingView,
            ticket: h.firstIndex(of: "trade #"),
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "type") ?? h.firstIndex(of: "side") ?? 0,
            shares: h.firstIndex(of: "contracts") ?? h.firstIndex(of: "qty") ?? 0,
            openTime: h.firstIndex(of: "date/time") ?? h.firstIndex(of: "date") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "price") ?? 0,
            closePrice: nil,
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "profit") ?? h.firstIndex(of: "cumulative profit") ?? 0,
            commission: nil,
            swap: nil,
            maePoints: h.firstIndex(of: "drawdown"),
            mfePoints: h.firstIndex(of: "run-up"),
            volume: nil,
            dateFormat: "yyyy-MM-dd'T'HH:mm:ssZ"
        )
    }

    private static func ninjaTraderMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .ninjaTrader,
            ticket: h.firstIndex(of: "trade #"),
            symbol: h.firstIndex(of: "instrument") ?? 0,
            direction: h.firstIndex(of: "market position") ?? 0,
            shares: h.firstIndex(of: "quantity") ?? h.firstIndex(of: "qty") ?? 0,
            openTime: h.firstIndex(of: "entry time") ?? 0,
            closeTime: h.firstIndex(of: "exit time"),
            openPrice: h.firstIndex(of: "entry price") ?? 0,
            closePrice: h.firstIndex(of: "exit price"),
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "profit") ?? h.firstIndex(of: "net profit") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: nil,
            maePoints: h.firstIndex(of: "mae"),
            mfePoints: h.firstIndex(of: "mfe"),
            volume: nil,
            dateFormat: "MM/dd/yyyy HH:mm:ss"
        )
    }

    private static func webullMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .webull,
            ticket: h.firstIndex(of: "order number") ?? h.firstIndex(of: "order id"),
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "side") ?? h.firstIndex(of: "action") ?? 0,
            shares: h.firstIndex(of: "filled qty") ?? h.firstIndex(of: "qty") ?? 0,
            openTime: h.firstIndex(of: "filled time") ?? h.firstIndex(of: "date") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "avg price") ?? h.firstIndex(of: "price") ?? 0,
            closePrice: nil,
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "realized p&l") ?? h.firstIndex(of: "p&l") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: nil,
            maePoints: nil,
            mfePoints: nil,
            volume: nil,
            dateFormat: "MM/dd/yyyy HH:mm:ss"
        )
    }

    // MARK: - Helpers

    /// Largest CSV we will read (broker exports are typically well under 10 MB)
    static let maxFileSize = 50 * 1024 * 1024

    private static func readFile(at path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw GenericParseError.fileNotFound((path as NSString).lastPathComponent)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= maxFileSize else {
            throw GenericParseError.fileTooLarge
        }
        if let str = try? String(contentsOfFile: path, encoding: .utf8) {
            return str
        } else if let str = try? String(contentsOfFile: path, encoding: .windowsCP1252) {
            return str
        }
        throw GenericParseError.encodingError
    }

    private static func splitLines(_ content: String) -> [String] {
        content.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private static func cleanSymbol(_ raw: String) -> String {
        let cleaned = raw.uppercased()
            .trimmingCharacters(in: .whitespaces)
        // Limit symbol length and strip non-alphanumeric (except dot for BRK.B etc.)
        let valid = cleaned.filter { $0.isLetter || $0.isNumber || $0 == "." }
        return String(valid.prefix(10))
    }

    /// Strip CSV formula injection prefixes from imported text fields
    private static func sanitizeImportField(_ field: String) -> String {
        guard let first = field.first, "=+@-\t\r".contains(first) else { return field }
        return String(field.dropFirst())
    }

    /// Largest share count / absolute amount accepted from a CSV. Rejects hostile values
    /// (inf, nan, 1e308) that would overflow later calculations.
    static let maxShares: Double = 1_000_000_000
    static let maxAbsAmount: Decimal = 1_000_000_000_000

    /// Parse a finite share quantity between `TradeLimits.minShares` and `maxShares`
    /// (commas allowed). Returns nil when invalid.
    static func parseShares(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value.isFinite else { return nil }
        let shares = abs(value)
        guard shares >= TradeLimits.minShares, shares <= maxShares else { return nil }
        return shares
    }

    /// Parse a money/price field ("$1,234.50", "(12.00)", "-3") within sane bounds.
    static func parseDecimal(_ raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let cleaned = stripCurrencyChars(raw)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, abs(value) <= maxAbsAmount else { return nil }
        return value
    }

    /// Parse a finite Double within the same bounds (MAE/MFE columns).
    static func parseBoundedDouble(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw.replacingOccurrences(of: ",", with: "")),
              value.isFinite, abs(value) <= maxShares else { return nil }
        return value
    }

    /// Strip currency symbols, parentheses (Robinhood debits), and whitespace from price/amount fields
    private static func stripCurrencyChars(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Handle parentheses for negative amounts: ($17150.00) → -17150.00
        if s.hasPrefix("(") && s.hasSuffix(")") {
            s = "-" + String(s.dropFirst().dropLast())
        }
        return s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func parseDateTime(_ string: String, format: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TradingCalendar.timeZone // brokers export exchange (ET) times

        let formats = [format, "yyyy-MM-dd HH:mm:ss", "MM/dd/yyyy HH:mm:ss",
                       "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd, HH:mm:ss",
                       "MM/dd/yy HH:mm:ss", "dd/MM/yyyy HH:mm:ss", "yyyy-MM-dd",
                       "M/d/yyyy", "MM/dd/yyyy", "MM/dd/yy", "M/d/yy"]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }

    // MARK: - Errors

    enum GenericParseError: LocalizedError {
        case fileNotFound(String)
        case encodingError
        case emptyFile
        case fileTooLarge
        case missingField(String, Int)
        case invalidDirection(String, Int)
        case invalidDate(String, Int)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let p): "File not found: \(p)"
            case .encodingError: "Could not read file — unsupported encoding"
            case .emptyFile: "CSV file is empty"
            case .fileTooLarge: "File is larger than 50 MB. Split it into smaller exports and import them one by one."
            case .missingField(let f, let l): "Missing required field '\(f)' at line \(l)"
            case .invalidDirection(let v, let l): "Cannot determine direction from '\(v)' at line \(l)"
            case .invalidDate(let v, let l): "Cannot parse date '\(v)' at line \(l)"
            }
        }
    }
}

// MARK: - Stable Ticket IDs

/// Turns row content into a stable positive 63-bit ID (FNV-1a). Identical rows inside one
/// file get distinct IDs via an occurrence counter, so genuine repeated fills are kept.
struct TicketKeyCounter {
    private var seen: [String: Int] = [:]

    mutating func ticket(for key: String) -> Int64 {
        let occurrence = seen[key, default: 0]
        seen[key] = occurrence + 1
        return Self.hash("\(key)#\(occurrence)")
    }

    static func hash(_ string: String) -> Int64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        let positive = Int64(bitPattern: value & 0x7FFF_FFFF_FFFF_FFFF)
        return positive == 0 ? 1 : positive
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
