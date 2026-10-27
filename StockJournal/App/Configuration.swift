import Foundation

/// App-wide constants and configuration
enum Configuration {
    /// Database filename
    static let databaseFilename = "Greenwick.sqlite"

    /// Minimum trades before generating recommendations
    static let minimumTradesForAnalysis = 30

    /// Optional AI analysis. Off by default; needs the user's own Anthropic key.
    enum AI {
        /// UserDefaults key for the explicit opt-in switch in Settings
        static let enabledKey = "ai_analysis_enabled"

        static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

        static var hasKey: Bool { !(KeychainHelper.anthropicAPIKey ?? "").isEmpty }

        static var isReady: Bool { isEnabled && hasKey }

        /// Plain statement of what leaves the Mac when the user runs an analysis
        static let dataSentDescription = """
            When you click Run Analysis, Greenwick sends summary statistics (overall totals, and P&L \
            by session, hour, ticker and weekday) to Anthropic's API, billed to your own API key. \
            Individual trades, notes, tags, screenshots and account details are not sent.
            """
    }

    /// US market session definitions (Eastern Time hours, 24h format)
    enum Session {
        static let preMarketStart = 4   // 4:00 AM ET
        static let regularStart = 9     // 9:30 AM ET (half-hour handled in Date+Market)
        static let regularEnd = 16      // 4:00 PM ET
        static let afterHoursEnd = 20   // 8:00 PM ET
    }
}
