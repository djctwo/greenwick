import SwiftUI

// MARK: - Getting Started

struct HelpGettingStarted: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Getting Started with Greenwick")
            HelpParagraph("Greenwick is a native Mac app for stock and day trade journaling and edge detection, with optional AI recommendations and live quotes. It analyzes your trading history to find where you make money, where you lose it, and what to do about it.")

            HelpSubtitle("First Launch")
            HelpParagraph("When you first open Greenwick, a welcome screen introduces the app's core features. Click \"Get Started\" to begin, or \"Load Sample Trades\" to start with 30 fictional trades to explore.")

            HelpSubtitle("Sample Trades")
            HelpParagraph("Sample trades are 30 made-up trades (fictional tickers, prices and results) for trying out the dashboard and analytics. Load them from the welcome screen or Settings > Data > Load Sample Trades; loading them again adds nothing new. Settings > Data > Remove Sample Trades deletes only those 30 and never touches trades you imported or entered.")

            HelpTip("You can import trades from any supported broker using CSV files. See Platform Import Guides for details.")

            HelpSubtitle("Your First Analysis")
            HelpParagraph("After importing trades, here's the recommended workflow:")
            HelpStep(number: 1, text: "Go to the Journal (Cmd+1) to review your imported trades. Use filters to explore by symbol, session, or date range.")
            HelpStep(number: 2, text: "Go to the Dashboard (Cmd+2) to see your portfolio overview — equity curve, win rate, profit factor, and key metrics.")
            HelpStep(number: 3, text: "Open Analytics (Cmd+3) for deep-dive analysis — 60+ components across Timing, Sessions, Symbols, Risk, Behavioral, and Advanced tabs.")
            HelpStep(number: 4, text: "Go to the Edge Report (Cmd+4) once you have 30+ trades. This shows your top money-makers and money-losers by session, hour, symbol, and day.")
            HelpStep(number: 5, text: "Browse Market for live ticker lookup and check your Watchlist for tracked symbols.")

            HelpSubtitle("Daily Routine")
            HelpBullet("After trading: Import your latest trades and review in the Journal. Add notes and tags.")
            HelpBullet("Weekly: Review the Edge Report and Dashboard for patterns. Run AI analysis for recommendations.")
            HelpBullet("Monthly: Check Monthly Returns, Growth Projection, and Consistency Score for long-term trends.")
        }
    }
}

// MARK: - Importing Trades

struct HelpImportingTrades: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Importing Trades")
            HelpParagraph("Greenwick supports importing trades from CSV files. You can import from any trading platform that exports trade history as CSV.")

            HelpSubtitle("Import Methods")

            HelpDefinition(term: "Drag and Drop", definition: "Drag a CSV file directly onto the Import tab's drop zone. The file will be parsed and imported automatically.")
            HelpDefinition(term: "File Picker", definition: "Click \"Choose File\" on the Import tab to open a file browser and select your CSV file.")
            HelpDefinition(term: "Batch Import", definition: "Select multiple CSV files at once to import your full trading history in one step.")

            HelpSubtitle("Duplicate Handling")
            HelpParagraph("Greenwick uses the ticket number as a unique identifier. If you import the same file twice, duplicate trades are automatically skipped. This means you can safely re-import without creating duplicate entries.")

            HelpSubtitle("After Import")
            HelpParagraph("After a successful import, Greenwick automatically navigates to the Dashboard so you can see your updated analytics. A success toast confirms how many trades were imported.")

            HelpSubtitle("Commissions and Fees")
            HelpParagraph("Imported P&L is net: any commission or fee column in the file is taken off each trade's profit, so every statistic is after costs. The costs are kept separately for the Commission Analytics card, and editing a trade's costs adjusts its P&L.")

            HelpSubtitle("Supported Platforms")
            HelpParagraph("See the Platform Import Guides section in the sidebar for step-by-step instructions for your specific trading platform: ThinkorSwim, Interactive Brokers, Webull, TradingView, NinjaTrader, and Generic CSV.")

            HelpTip("Import at least 30 trades to unlock the Edge Report and get meaningful analytics. The more history you import, the more reliable the pattern detection becomes.")

            HelpSubtitle("Import Errors")
            HelpParagraph("If an import fails, Greenwick shows an error message explaining what went wrong:")
            HelpBullet("\"Column mismatch\" — The CSV format doesn't match. Check that you're using the correct export from your platform.")
            HelpBullet("\"Unsupported encoding\" — The file uses an uncommon character encoding. Try re-exporting as UTF-8.")
            HelpBullet("\"No trade detail section found\" — The CSV doesn't contain the expected trade data section.")
        }
    }
}

// MARK: - Exporting Data

struct HelpExportingData: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Exporting Data")
            HelpParagraph("Greenwick supports exporting your trade data and analytics reports in multiple formats.")

            HelpSubtitle("CSV Export")
            HelpParagraph("Export your full trade data as a CSV file.")
            HelpBullet("Available from the Journal and Dashboard toolbar export menu.")
            HelpBullet("Includes 27 columns covering all trade details, metrics, and tags.")
            HelpBullet("Formula injection prevention: fields starting with =, +, @, or - are safely escaped, and control characters (such as stray line breaks) are removed so no field can split a row.")
            HelpBullet("UTF-8 encoded, compatible with Excel, Google Sheets, and Numbers.")

            HelpSubtitle("PDF Export")
            HelpParagraph("Export formatted reports as multi-page PDF documents.")
            HelpBullet("Journal Report: Trade list table with summary metrics (P&L, win rate, profit factor, expectancy, streaks, drawdown).")
            HelpBullet("Dashboard Report: Key metrics, grade distribution, performance tables by session/symbol/day/hour, monthly P&L, risk assessment.")
            HelpBullet("Edge Report: edge breakdowns by session, hour, symbol and day, plus AI recommendations if you ran them.")

            HelpSubtitle("Data Backup")
            HelpParagraph("Back up your whole journal from Settings > Data > Back Up Journal. The backup file contains all your trades, notes, tags, checkpoints and settings. Screenshots attached to trades are not included (a trade keeps only their file names); they stay encrypted in Greenwick's data folder, readable only with this installation's journal key. You can restore from a backup at any time with Restore Backup.")
            HelpParagraph("Turn on \"Protect this backup with a password\" (on by default when App Lock is on) to encrypt the backup: AES-256-GCM with a key derived from the password (PBKDF2-SHA256, 600,000 rounds, minimum 8 characters). Without that password the backup can't be restored, and Greenwick can't recover it for you.")
            HelpWarning("A backup without a password is a plain, unencrypted copy of your journal: anyone who gets the file can read it. Protecting backups with a password is recommended.")
            HelpParagraph("When you restore a password-protected backup, Greenwick asks for its password. A wrong password changes nothing; you can try again or cancel. Backups protected by older versions of Greenwick still restore with their password.")
            HelpParagraph("Before a restore replaces your journal, Greenwick checks the backup in memory: it must be a Greenwick database with nothing extra in it, and every trade must have sensible values (the same limits as a CSV import). If anything is off, the restore is refused with the reason and your journal stays as it was. Only the checked trades, checkpoints and settings are copied into your journal, never the backup file itself.")
        }
    }
}
