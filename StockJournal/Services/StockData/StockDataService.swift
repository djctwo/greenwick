import SwiftUI
import os

/// Fetches real-time stock data from the Finnhub API (https://finnhub.io/api/v1/)
///
/// API key is stored in macOS Keychain and entered by the user in Settings.
/// Quote data is cached with a 30-second TTL to avoid unnecessary API calls.
///
/// Wire into AppState: `let stockDataService = StockDataService()`
@Observable @MainActor
final class StockDataService {
    // MARK: - API Key

    /// Finnhub API key stored securely in macOS Keychain
    var apiKey: String {
        get { KeychainHelper.finnhubAPIKey ?? "" }
        set { KeychainHelper.finnhubAPIKey = newValue.isEmpty ? nil : newValue }
    }

    /// Whether the user has configured a Finnhub API key
    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: - State

    var isLoading = false
    var errorMessage: String?

    // MARK: - Private

    private static let logger = Logger(subsystem: "com.greenwick", category: "StockData")
    private static let baseURL = "https://finnhub.io/api/v1"
    private static let cacheTTL: TimeInterval = 30

    private var quoteCache: [String: (quote: StockQuote, fetched: Date)] = [:]
    private var profileCache: [String: CompanyProfile] = [:]

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case noAPIKey
        case invalidURL
        case rateLimited
        case httpError(Int)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                "No Finnhub API key configured. Add your key in Settings."
            case .invalidURL:
                "Invalid request URL."
            case .rateLimited:
                "API rate limit reached. Using cached data."
            case .httpError(let code):
                "Server error (HTTP \(code))."
            case .decodingFailed(let detail):
                "Failed to parse response: \(detail)"
            }
        }
    }

    // MARK: - Public API

    /// Fetch a real-time quote for a symbol. Returns cached data if within TTL.
    func fetchQuote(symbol: String) async throws -> StockQuote {
        let uppercased = symbol.uppercased()

        // Return cached quote if fresh
        if let cached = quoteCache[uppercased],
           Date().timeIntervalSince(cached.fetched) < Self.cacheTTL {
            Self.logger.debug("Quote cache hit for \(uppercased)")
            return cached.quote
        }

        let quote: StockQuote = try await request(
            endpoint: "/quote",
            params: ["symbol": uppercased]
        )

        quoteCache[uppercased] = (quote: quote, fetched: Date())
        Self.logger.debug("Fetched quote for \(uppercased)")
        return quote
    }

    /// Fetch company profile for a symbol. Profiles are cached indefinitely (they rarely change).
    func fetchProfile(symbol: String) async throws -> CompanyProfile {
        let uppercased = symbol.uppercased()

        if let cached = profileCache[uppercased] {
            Self.logger.debug("Profile cache hit for \(uppercased)")
            return cached
        }

        let profile: CompanyProfile = try await request(
            endpoint: "/stock/profile2",
            params: ["symbol": uppercased]
        )

        profileCache[uppercased] = profile
        Self.logger.info("Fetched profile for \(uppercased): \(profile.name)")
        return profile
    }

    /// Search for symbols matching a query string
    func searchSymbols(query: String) async throws -> [SymbolSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response: SymbolSearchResponse = try await request(
            endpoint: "/search",
            params: ["q": trimmed]
        )

        // Filter to common stock types, limit results
        let filtered = response.result
            .filter { $0.type == "Common Stock" || $0.type == "ETP" || $0.type.isEmpty }
            .prefix(10)

        Self.logger.info("Search '\(trimmed)' returned \(filtered.count) results")
        return Array(filtered)
    }

    /// Fetch earnings calendar for a date range. Returns events for all symbols.
    func fetchEarnings(from startDate: Date, to endDate: Date) async throws -> [EarningsEvent] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let response: EarningsCalendarResponse = try await request(
            endpoint: "/calendar/earnings",
            params: [
                "from": formatter.string(from: startDate),
                "to": formatter.string(from: endDate),
            ]
        )

        Self.logger.info("Fetched \(response.earningsCalendar.count) earnings events")
        return response.earningsCalendar
    }

    /// Clear all cached data
    func clearCache() {
        quoteCache.removeAll()
        profileCache.removeAll()
        Self.logger.info("Cache cleared")
    }

    // MARK: - Private Networking

    private static let session = CertificatePinningDelegate.pinnedSession(timeout: 30)

    private func request<T: Decodable>(endpoint: String, params: [String: String]) async throws -> T {
        guard hasAPIKey else {
            throw ServiceError.noAPIKey
        }

        var components = URLComponents(string: Self.baseURL + endpoint)
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components?.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            Self.logger.error("Network error: \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.httpError(0)
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            Self.logger.warning("Rate limited on \(endpoint)")
            throw ServiceError.rateLimited
        default:
            Self.logger.error("HTTP \(httpResponse.statusCode) on \(endpoint)")
            throw ServiceError.httpError(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            #if DEBUG
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "n/a"
            Self.logger.debug("Decode error on \(endpoint): \(error.localizedDescription) — body: \(bodyPreview)")
            #else
            Self.logger.error("Decode error on \(endpoint): \(error.localizedDescription)")
            #endif
            throw ServiceError.decodingFailed(error.localizedDescription)
        }
    }
}
