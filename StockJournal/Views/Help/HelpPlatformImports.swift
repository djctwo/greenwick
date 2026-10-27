import SwiftUI

// MARK: - TradingView

struct HelpImportTradingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from TradingView")
            HelpParagraph("TradingView supports paper trading and broker-connected trading. You can export your trade history from both.")

            HelpSubtitle("Paper Trading Export")
            HelpStep(number: 1, text: "Open TradingView and go to the Bottom Panel > Trading Panel.")
            HelpStep(number: 2, text: "Click the \"History\" tab to see your closed paper trades.")
            HelpStep(number: 3, text: "Click the gear/settings icon and select \"Export trade list\" or right-click > Export.")
            HelpStep(number: 4, text: "Save as CSV and import into Greenwick.")

            HelpSubtitle("Broker-Connected Trading")
            HelpParagraph("If you trade through a broker connected to TradingView, your trade history is stored by the broker. Export directly from your broker's platform instead — it will have more detailed data.")

            HelpSubtitle("Strategy Tester / Backtests")
            HelpStep(number: 1, text: "After running a Pine Script strategy, go to the Strategy Tester panel.")
            HelpStep(number: 2, text: "Click the \"List of Trades\" tab.")
            HelpStep(number: 3, text: "Click the export icon to download as CSV.")
            HelpStep(number: 4, text: "Import into Greenwick to analyze your backtest results.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("TradingView exports vary by source. Common columns include: Trade #, Type (Long/Short), Signal, Date/Time, Price, Shares, Profit, Cumulative Profit, Run-up, Drawdown.")
        }
    }
}

// MARK: - Interactive Brokers

struct HelpImportIB: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Interactive Brokers")
            HelpParagraph("Interactive Brokers (IBKR) provides detailed trade reports through their Client Portal and Flex Query system.")

            HelpSubtitle("Option A: Activity Statement (Simple)")
            HelpStep(number: 1, text: "Log in to Client Portal at portal.interactivebrokers.com.")
            HelpStep(number: 2, text: "Go to Performance & Reports > Statements.")
            HelpStep(number: 3, text: "Select \"Activity\" statement type and choose your date range.")
            HelpStep(number: 4, text: "Choose CSV format and download.")
            HelpStep(number: 5, text: "The downloaded file may contain multiple sections. Look for the \"Trades\" section.")
            HelpStep(number: 6, text: "Import into Greenwick.")

            HelpSubtitle("Option B: Flex Query (Advanced)")
            HelpParagraph("Flex Queries give you more control over which fields to export:")
            HelpStep(number: 1, text: "In Client Portal, go to Performance & Reports > Flex Queries.")
            HelpStep(number: 2, text: "Create a new Flex Query for \"Trades\" with fields: TradeID, Symbol, Side, Quantity, TradeDate, TradeTime, TradePrice, ClosePrice, Commission, NetCash, CurrencyPrimary.")
            HelpStep(number: 3, text: "Run the query and download as CSV.")
            HelpStep(number: 4, text: "Import into Greenwick.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("IB exports typically include: TradeID, Symbol, Date/Time, Quantity, T.Price (trade price), C.Price (close price), Proceeds, Comm/Fee, Realized P/L, Code.")

            HelpWarning("IB uses negative quantity for sell/short trades and positive for buy/long. Greenwick handles this conversion automatically.")
        }
    }
}

// MARK: - Thinkorswim

struct HelpImportThinkorswim: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Thinkorswim")
            HelpParagraph("Thinkorswim (by Schwab, formerly TD Ameritrade) provides trade history export through the platform's account statement.")

            HelpSubtitle("How to Export")
            HelpStep(number: 1, text: "Open Thinkorswim desktop platform.")
            HelpStep(number: 2, text: "Go to Monitor > Account Statement.")
            HelpStep(number: 3, text: "Set your date range at the top.")
            HelpStep(number: 4, text: "Scroll down to the \"Trade History\" section.")
            HelpStep(number: 5, text: "Right-click on the trade history table and select \"Export to File\" or \"Copy to Clipboard\".")
            HelpStep(number: 6, text: "If copying to clipboard, paste into a spreadsheet and save as CSV.")
            HelpStep(number: 7, text: "Import the CSV into Greenwick.")

            HelpSubtitle("Alternative: Web Export")
            HelpStep(number: 1, text: "Log in to schwab.com.")
            HelpStep(number: 2, text: "Navigate to Accounts > History & Statements.")
            HelpStep(number: 3, text: "Select \"Transaction History\" and filter for trades.")
            HelpStep(number: 4, text: "Download as CSV.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("Thinkorswim exports include: Exec Time, Side (BOT/SLD), Qty, Symbol, Price, Net Price, Order Type, Commission.")

            HelpTip("Thinkorswim uses \"BOT\" for buy and \"SLD\" for sell. Greenwick recognizes both formats.")
        }
    }
}

// MARK: - NinjaTrader

struct HelpImportNinjaTrader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from NinjaTrader")
            HelpParagraph("NinjaTrader is popular for futures and stock day trading. You can export trade performance reports as CSV.")

            HelpSubtitle("How to Export")
            HelpStep(number: 1, text: "Open NinjaTrader 8.")
            HelpStep(number: 2, text: "Go to the Control Center > New > Trade Performance.")
            HelpStep(number: 3, text: "In the Trade Performance window, select your account and date range.")
            HelpStep(number: 4, text: "Click the \"Executions\" or \"Trades\" tab to see individual trades.")
            HelpStep(number: 5, text: "Right-click on the data grid and select \"Export\" > \"CSV\".")
            HelpStep(number: 6, text: "Save the file and import into Greenwick.")

            HelpSubtitle("Alternative: Account Data Export")
            HelpStep(number: 1, text: "In NinjaTrader, go to Tools > Account Data.")
            HelpStep(number: 2, text: "Select \"Orders\" or \"Executions\".")
            HelpStep(number: 3, text: "Export as CSV.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("NinjaTrader exports typically include: Trade #, Instrument, Market Position (Long/Short), Quantity, Entry Time, Entry Price, Exit Time, Exit Price, Profit, Commission, MAE, MFE.")

            HelpTip("NinjaTrader includes MAE and MFE in its exports, which gives Greenwick more data to work with for trade quality analysis and grading.")
        }
    }
}

// MARK: - Webull

struct HelpImportWebull: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Webull")
            HelpParagraph("Webull provides detailed trade history exports.")

            HelpSubtitle("How to Export")
            HelpStep(number: 1, text: "Open Webull desktop or mobile app.")
            HelpStep(number: 2, text: "Go to Account > Trade History.")
            HelpStep(number: 3, text: "Select date range and click Export.")
            HelpStep(number: 4, text: "Save as CSV and import into Greenwick.")

            HelpTip("Webull exports include commission and fee data. Greenwick imports this automatically.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("Webull exports typically include: Symbol, Side (Buy/Sell), Quantity, Price, Filled Time, Status, Commission, Realized P&L.")
        }
    }
}

// MARK: - Generic CSV

struct HelpImportGenericCSV: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Generic CSV")
            HelpParagraph("If your broker or platform isn't listed above, you can import trades using a generic CSV file. Greenwick will map common column names automatically.")

            HelpSubtitle("Required Columns")
            HelpBullet("Symbol — The stock ticker (e.g., AAPL, TSLA, SPY).")
            HelpBullet("Side / Direction — BUY or SELL (also accepts LONG/SHORT, BOT/SLD).")
            HelpBullet("Quantity / Shares — Number of shares traded.")
            HelpBullet("Entry Price — The price at which you entered the trade.")
            HelpBullet("Exit Price — The price at which you exited the trade.")
            HelpBullet("Entry Time — Date and time of trade entry.")
            HelpBullet("Exit Time — Date and time of trade exit.")

            HelpSubtitle("Optional Columns")
            HelpBullet("P&L / Profit — Net profit or loss (calculated from prices if missing).")
            HelpBullet("Commission — Trading fees paid.")
            HelpBullet("Stop Loss / Take Profit — Pre-set exit levels.")
            HelpBullet("Notes / Comment — Free-text trade notes.")

            HelpSubtitle("Formatting Tips")
            HelpBullet("Save the file as UTF-8 encoded CSV.")
            HelpBullet("Use standard date formats (YYYY-MM-DD HH:MM:SS or MM/DD/YYYY HH:MM).")
            HelpBullet("Column names are matched case-insensitively.")
            HelpBullet("Extra columns are ignored — Greenwick only reads what it recognizes.")

            HelpTip("Export a sample CSV from Settings > Data > Export to see the exact format Greenwick expects. Match your file to that layout for guaranteed compatibility.")
        }
    }
}
