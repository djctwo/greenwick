import SwiftUI

// MARK: - Journal

struct HelpJournal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Trade Journal")
            HelpParagraph("The Journal is your complete trade log. Every imported trade appears here with full details, filtering, search, and export capabilities.")

            HelpSubtitle("Trade Table")
            HelpParagraph("The table shows 10 columns for each trade:")
            HelpBullet("Close Time — When the trade closed (click to open full detail sheet).")
            HelpBullet("Symbol — Stock ticker with color-coded icon.")
            HelpBullet("Direction — BUY or SELL badge.")
            HelpBullet("Shares — Position size.")
            HelpBullet("P&L — Net profit/loss, green for wins, red for losses.")
            HelpBullet("Cumulative P&L — Running total from earliest to current trade.")
            HelpBullet("R-Multiple — Risk-adjusted return (how many R you made/lost).")
            HelpBullet("Grade — A-F quality score based on execution, timing, and management.")
            HelpBullet("Session — Market session badge (Pre-Market, Regular, After-Hours).")
            HelpBullet("Hour — ET hour the trade was taken.")

            HelpSubtitle("Filters")
            HelpBullet("Symbol: Filter by specific stock symbol.")
            HelpBullet("Session: Filter by market session (Pre-Market, Regular, After-Hours, Extended).")
            HelpBullet("Direction: Show only BUY or SELL trades.")
            HelpBullet("Date Range: Today, This Week, This Month, Last 30/90 Days, or All Time.")
            HelpBullet("Sort: Newest/Oldest first, Best/Worst P&L, Largest Win/Loss.")
            HelpBullet("Search: Search by symbol, ticket number, comment, notes, or tags.")

            HelpSubtitle("Performance Strip")
            HelpParagraph("Below the filters, a summary strip shows key metrics for your currently filtered trades: P&L, Win Rate, Profit Factor, Expectancy, Avg R, and Current Streak.")

            HelpSubtitle("Trade Detail Sheet")
            HelpParagraph("Click any trade to open a detail sheet showing all 32+ fields organized by section: Trade Info, Prices, Performance, Advanced metrics, Tags, Notes, and Metadata.")

            HelpSubtitle("Tags and Notes")
            HelpParagraph("Each trade can have user-defined tags (e.g., \"setup-A\", \"sniper\", \"revenge\") and free-text notes for trade reflections. Tags help you track which types of trades are profitable. Quick-suggest buttons offer common tags.")

            HelpTip("Use consistent tags like \"setup-A\" or \"news-trade\" to track which setups generate edge. View tag analytics in the Edge Report.")
        }
    }
}

// MARK: - Dashboard

struct HelpDashboard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Dashboard")
            HelpParagraph("The Dashboard is your analytics command center with 66 components organized across 6 tabs: Timing, Sessions, Symbols, Risk, Behavioral, and Advanced. All components react to the symbol and date range filters in the toolbar.")

            HelpSubtitle("Toolbar Filters")
            HelpBullet("Symbol Filter: Narrow all analytics to a specific stock symbol, or view All Symbols.")
            HelpBullet("Date Range: All Time, This Week, This Month, Last 30 Days, Last 90 Days.")
            HelpBullet("Export: Save a PDF or CSV report of your dashboard data.")

            HelpSubtitle("Key Sections")
            HelpDefinition(term: "Quick Insight", definition: "A rotating data-driven insight bar at the top. It highlights your strongest pattern each day — best session, worst symbol, win streak record, Sharpe warnings, or drawdown alerts.")
            HelpDefinition(term: "Metric Cards (12)", definition: "P&L, Win Rate, Profit Factor, Expectancy, Avg Win/Loss, Max Drawdown, Avg R-Multiple, Streaks, Avg Duration, Sharpe Ratio, Calmar Ratio. Each shows the primary metric with supporting context.")
            HelpDefinition(term: "Equity Curve", definition: "Your cumulative P&L plotted over time. An upward-trending curve indicates consistent edge.")
            HelpDefinition(term: "Drawdown Chart", definition: "Shows how far below peak equity you are at any point. Deeper drawdowns mean higher risk periods.")
            HelpDefinition(term: "Trade Calendar", definition: "Color-coded grid showing P&L per day. Green = profitable day, Red = losing day. Spot patterns at a glance.")

            HelpParagraph("See the Analytics Components help topic for detailed explanations of all 66 components.")

            HelpTip("Use the symbol filter to isolate analytics for a specific stock. This reveals symbol-specific edge that might be hidden in portfolio-level data.")
        }
    }
}

// MARK: - Edge Report

struct HelpEdgeReport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Edge Report")
            HelpParagraph("The Edge Report answers the most important question in trading: where exactly do you make and lose money? It requires at least 30 trades to generate meaningful analysis.")

            HelpSubtitle("Edge Breakdowns")
            HelpParagraph("Four cards show your top 5 money-makers and top 5 money-losers across four dimensions:")
            HelpBullet("By Session: Which sessions (Pre-Market, Regular, After-Hours) are most/least profitable.")
            HelpBullet("By Hour: Which ET hours produce the best/worst results.")
            HelpBullet("By Symbol: Which stock symbols make/lose the most money.")
            HelpBullet("By Day: Which weekdays are strongest/weakest.")
            HelpParagraph("Each entry shows P&L in dollars, trade count, and win rate. Dollar values make the impact concrete — \"Regular session: +$2,340 over 45 trades\" is actionable.")

            HelpSubtitle("AI Analysis")
            HelpParagraph("Optional. If you add your own Anthropic API key and switch on AI analysis in Settings, click \"Run Analysis\" to get 3-5 ranked recommendations with dollar impact estimates. Only summary statistics are sent. See the AI Analysis help topic for details.")
        }
    }
}

// MARK: - Trade Replay

struct HelpTradeReplay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Trade Replay")
            HelpParagraph("Trade Replay lets you step through your trades chronologically, watching your equity curve build trade by trade. It's a powerful learning tool for reviewing what happened and when.")

            HelpSubtitle("How to Use")
            HelpStep(number: 1, text: "Go to the Journal tab (Cmd+1).")
            HelpStep(number: 2, text: "Click the \"Replay\" button in the toolbar (requires 2+ trades).")
            HelpStep(number: 3, text: "Use the controls to step through trades or play automatically.")

            HelpSubtitle("Controls")
            HelpBullet("Play/Pause: Automatically advance through trades at the selected speed.")
            HelpBullet("Step Forward/Back: Move one trade at a time.")
            HelpBullet("Rewind: Jump back to the first trade.")
            HelpBullet("Skip to End: Jump to the last trade.")
            HelpBullet("Speed: Adjust playback speed (0.5x, 1x, 2x, 5x).")

            HelpSubtitle("What You See")
            HelpBullet("Equity Curve: Builds in real-time as you step through trades, with a marker on the current position.")
            HelpBullet("Running Stats: Live-updating P&L, win/loss count, win rate, and current streak.")
            HelpBullet("Trade Card: Full details of the current trade — symbol, direction, session, time, R-multiple, MAE, MFE, and running context (progress through total trades, average P&L, peak equity, current drawdown).")

            HelpTip("Use replay to study your losing streaks. Step through slowly and look for patterns — were you overtrading? Trading the wrong session? Holding losers too long?")
        }
    }
}
