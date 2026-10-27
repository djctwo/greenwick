import Foundation

// MARK: - Stock Quote

/// Real-time price data from Finnhub /quote endpoint
struct StockQuote: Codable, Sendable {
    let currentPrice: Double
    let change: Double
    let percentChange: Double
    let high: Double
    let low: Double
    let open: Double
    let previousClose: Double
    let timestamp: Int

    var isPositive: Bool { change >= 0 }

    var formattedPrice: String {
        String(format: "$%.2f", currentPrice)
    }

    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@$%.2f (%@%.2f%%)", sign, abs(change), sign, abs(percentChange))
    }

    private enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case change = "d"
        case percentChange = "dp"
        case high = "h"
        case low = "l"
        case open = "o"
        case previousClose = "pc"
        case timestamp = "t"
    }
}

// MARK: - Company Profile

/// Company information from Finnhub /stock/profile2 endpoint
struct CompanyProfile: Codable, Sendable {
    let name: String
    let ticker: String
    let exchange: String
    let industry: String
    let marketCap: Double
    let sharesOutstanding: Double
    let logo: String
    let weburl: String
    let ipo: String
    let country: String

    /// Market cap formatted as human-readable string (e.g., "$2.87T", "$450.2B")
    var formattedMarketCap: String {
        let value = marketCap // Finnhub returns in millions
        if value >= 1_000_000 {
            return String(format: "$%.2fT", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fB", value / 1_000)
        } else {
            return String(format: "$%.1fM", value)
        }
    }

    /// Shares outstanding formatted (e.g., "15.3B", "450.2M")
    var formattedShares: String {
        if sharesOutstanding >= 1_000 {
            return String(format: "%.1fB", sharesOutstanding / 1_000)
        } else {
            return String(format: "%.1fM", sharesOutstanding)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case ticker
        case exchange
        case industry = "finnhubIndustry"
        case marketCap = "marketCapitalization"
        case sharesOutstanding = "shareOutstanding"
        case logo
        case weburl
        case ipo
        case country
    }
}

// MARK: - Symbol Search Result

/// Search result from Finnhub /search endpoint
struct SymbolSearchResult: Codable, Sendable, Identifiable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String

    var id: String { symbol }
}

/// Wrapper for the Finnhub search response
struct SymbolSearchResponse: Codable, Sendable {
    let count: Int
    let result: [SymbolSearchResult]
}

// MARK: - Earnings Calendar

/// Earnings event from Finnhub /calendar/earnings endpoint
struct EarningsEvent: Codable, Sendable, Identifiable {
    let date: String            // "2026-04-25"
    let epsActual: Double?      // actual EPS
    let epsEstimate: Double?    // estimated EPS
    let revenueActual: Double?  // actual revenue
    let revenueEstimate: Double? // estimated revenue
    let symbol: String
    let hour: String            // "bmo" (before market open), "amc" (after market close)

    var id: String { "\(symbol)-\(date)" }
}

/// Wrapper for the Finnhub earnings calendar response
struct EarningsCalendarResponse: Codable, Sendable {
    let earningsCalendar: [EarningsEvent]
}
