import SwiftUI

// MARK: - Settings

struct HelpSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Settings")
            HelpParagraph("Access Settings via Cmd+, or the Settings tab in the sidebar.")

            HelpSubtitle("AI Analysis")
            HelpParagraph("Optional and off by default. Switch on \"Allow AI analysis\" and enter your own Anthropic API key to get AI recommendations in the Edge Report. The key is stored in your macOS Keychain and only sent to Anthropic's API over HTTPS. Anthropic bills your account.")

            HelpSubtitle("Market Data")
            HelpParagraph("Optional. Enter your own free Finnhub API key (finnhub.io/register) to enable quotes, ticker search and company profiles in Browse and Watchlist. Only ticker symbols are sent to Finnhub.")

            HelpSubtitle("Data Management")
            HelpBullet("Trade Count: Shows how many trades are in your database.")
            HelpBullet("Back Up Journal: Save a full copy of your journal, optionally protected with a password (recommended; without one, anyone who gets the file can read it).")
            HelpBullet("Restore Backup: Replace your journal with a backup. A password-protected backup asks for its password. If the password is wrong or the file is not a valid backup, nothing is changed.")
            HelpBullet("Delete All Trades: Removes all trade data after confirmation. You have 5 seconds to undo.")

            HelpSubtitle("Security")
            HelpParagraph("Enable or disable App Lock, change its password, and choose \"Lock after inactivity\" (Off, 1, 5, 15, 30 or 60 minutes; 15 by default). With App Lock on, your journal can only be decrypted with the password. See the App Lock help topic for details.")

            HelpSubtitle("About")
            HelpParagraph("Shows app version, build number, database and license info.")
        }
    }
}

// MARK: - App Lock

struct HelpAppLock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("App Lock")
            HelpParagraph("App Lock protects your journal with a password. The journal is always stored encrypted; with App Lock on, the key that decrypts it is itself encrypted with your password, so nothing can be read until you enter it, even by someone who opens Greenwick or copies its files.")

            HelpSubtitle("Enabling App Lock")
            HelpStep(number: 1, text: "Go to Settings > Security.")
            HelpStep(number: 2, text: "Click \"Enable App Lock\".")
            HelpStep(number: 3, text: "Enter a password (minimum 8 characters) and confirm it.")
            HelpStep(number: 4, text: "App Lock is now active. Greenwick asks for the password at every launch, locks again when it goes to the background, and locks after 15 minutes without keyboard or mouse activity in the app (change this, or turn it off, under \"Lock after inactivity\"). If an unlock or an App Lock change is still running at that moment, Greenwick locks as soon as it finishes.")

            HelpSubtitle("Security Details")
            HelpBullet("Your journal is encrypted with AES-256-GCM and never written to disk unencrypted, not even while Greenwick is open.")
            HelpBullet("Screenshots you attach to trades are encrypted with the journal's key too. They are decrypted only in memory to show them, and never while Greenwick is locked. Screenshots saved by an older version of Greenwick (plain image files) are encrypted the first time you open or unlock this version.")
            HelpBullet("With App Lock on, the journal's key is sealed with a key derived from your password (PBKDF2-SHA256, 600,000 rounds). Your password itself is never saved.")
            HelpBullet("Turning App Lock on, and every password change, gives the journal and its screenshots a brand-new key, so an old copy of a previous key can't open them.")
            HelpBullet("Nothing is decrypted until the right password is entered. Locking (or quitting) saves and closes the journal and forgets the key. Locking also closes open dialogs, such as a backup's save panel. If the journal can't be saved at that moment (for example the disk is full), Greenwick keeps it in memory behind the lock screen so your latest changes aren't lost, and saves it when you unlock.")
            HelpBullet("Every save of the journal is numbered, and the number of the last save is kept in your Keychain. If the journal file is ever replaced by an older copy, Greenwick doesn't open it silently: it says the journal is older than the last one this Mac saved and asks whether to open it anyway (with App Lock on, you must enter the password again). Restoring a backup from Settings doesn't trigger this.")
            HelpBullet("After 5 wrong passwords, Greenwick makes you wait before trying again, longer each time.")
            HelpBullet("Changing the password or turning App Lock off (Settings > Security) asks for the current password. Wrong passwords there count toward the same limit as on the lock screen.")
            HelpBullet("If Greenwick can't rewrite the journal or a screenshot while you turn App Lock on or change its password (for example because the disk is full, or Greenwick quits in the middle), the new password is already the one that unlocks. Greenwick finishes re-encrypting them the next time you unlock with it; until a screenshot is done, changing the password again or turning App Lock off is refused, so its old key isn't lost. Until then the old key stays in your Keychain: after a password change it is protected by the new password, but after turning App Lock on it is still stored the way it was with App Lock off, so lock and unlock Greenwick soon to finish. A lock asked for while you change App Lock waits until the change is done.")
            HelpBullet("Wrong passwords, lockouts and every change to App Lock are recorded in the macOS log (Console app, subsystem com.greenwick), so you can see if someone tried. Passwords and keys are never logged.")

            HelpSubtitle("Forgot Your Password?")
            HelpParagraph("When you turn App Lock on, Greenwick also keeps a copy of the journal key that macOS releases only after Touch ID or your Mac login password. If you forget your password, click \"Forgot Password?\" on the lock screen and confirm with Touch ID or your Mac password. This removes the app password and keeps all your trade data. You can set a new password afterward in Settings. If a password change was interrupted, the Touch ID copy is brought up to date the next time you unlock with your password; until then it may no longer open the journal, and Greenwick says so and offers to erase all local data instead.")
            HelpParagraph("Copies of Greenwick built without an Apple developer signature can't keep that protected copy (Settings tells you when you turn the lock on). For those, a forgotten password can't be recovered: \"Forgot Password?\" can only erase all local data so you can start fresh, after you confirm with Touch ID or your Mac login password (so nobody else at your Mac can erase your journal from the lock screen).")

            HelpWarning("Backups you export without a password are unencrypted copies of the journal (backups don't include screenshots), and your watchlist symbols, checklist rules, the inactivity lock setting and display preferences are kept in Greenwick's ordinary preferences file. (Prop firm account size and limits are stored inside the encrypted journal.) Turn on FileVault (System Settings > Privacy & Security > FileVault) to protect everything on your Mac.")
        }
    }
}

// MARK: - Keyboard Shortcuts

struct HelpKeyboardShortcuts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Keyboard Shortcuts")
            HelpParagraph("Navigate Greenwick quickly using these keyboard shortcuts.")

            HelpSubtitle("Navigation")
            shortcutRow("Journal", "Cmd + 1")
            shortcutRow("Dashboard", "Cmd + 2")
            shortcutRow("Analytics", "Cmd + 3")
            shortcutRow("Edge Report", "Cmd + 4")
            shortcutRow("Import", "Cmd + 5")
            shortcutRow("Settings", "Cmd + ,")
            shortcutRow("New Trade", "Cmd + N")
            shortcutRow("Import File", "Cmd + I")

            HelpSubtitle("General")
            shortcutRow("Confirm / Submit", "Return")
            shortcutRow("Cancel / Dismiss", "Escape")
            shortcutRow("Unlock App", "Return")
        }
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(shortcut)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Glossary

struct HelpGlossary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Glossary")
            HelpParagraph("Key trading and analytics terms used in Greenwick.")

            HelpSubtitle("Trading Terms")
            HelpDefinition(term: "Shares", definition: "The number of shares traded in a position.")
            HelpDefinition(term: "Point", definition: "A $1 move in the stock price.")
            HelpDefinition(term: "Spread", definition: "The difference between bid and ask price. Your cost of entering a trade.")
            HelpDefinition(term: "Slippage", definition: "The difference between your expected fill price and actual fill price. Higher during news events or low liquidity.")
            HelpDefinition(term: "Stop Loss (SL)", definition: "A pre-set price level where your trade automatically closes to limit losses.")
            HelpDefinition(term: "Take Profit (TP)", definition: "A pre-set price level where your trade automatically closes to lock in profits.")

            HelpSubtitle("Session Terms")
            HelpDefinition(term: "Pre-Market", definition: "4:00-9:30 ET. Early trading session before the opening bell. Lower volume, wider spreads, often driven by overnight news and earnings releases.")
            HelpDefinition(term: "Regular Session", definition: "9:30-16:00 ET. The standard US stock market session. Highest volume and liquidity.")
            HelpDefinition(term: "After-Hours", definition: "16:00-20:00 ET. Post-close trading session. Lower volume, often reacts to earnings releases and after-hours news.")
            HelpDefinition(term: "Extended", definition: "Other hours outside the three main sessions. Very low liquidity.")
            HelpDefinition(term: "Kill Zone", definition: "Specific high-probability time windows within sessions where institutional order flow concentrates (e.g., opening 15 minutes, power hour).")

            HelpSubtitle("Analytics Terms")
            HelpDefinition(term: "MAE (Maximum Adverse Excursion)", definition: "The worst drawdown during a trade. How far price moved against you before the trade closed.")
            HelpDefinition(term: "MFE (Maximum Favorable Excursion)", definition: "The best unrealized profit during a trade. How far price moved in your favor before the trade closed.")
            HelpDefinition(term: "R-Multiple", definition: "Profit/loss as a multiple of initial risk. 2R = you made 2x your risk. -0.5R = you lost half your risk.")
            HelpDefinition(term: "Profit Factor", definition: "Gross profit / gross loss. Above 1.0 = profitable. Above 2.0 = excellent.")
            HelpDefinition(term: "Expectancy", definition: "Average expected profit per trade. (Win% x Avg Win) - (Loss% x Avg Loss).")
            HelpDefinition(term: "Sharpe Ratio", definition: "Risk-adjusted return metric. Average return / standard deviation of returns. Higher = better.")
            HelpDefinition(term: "Calmar Ratio", definition: "Annualized return / max drawdown. Measures return per unit of drawdown risk.")
            HelpDefinition(term: "Kelly Criterion", definition: "Optimal bet sizing formula based on win rate and reward-to-risk ratio.")

        }
    }
}

// MARK: - FAQ

struct HelpFAQ: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Frequently Asked Questions")

            faqItem(
                question: "How many trades do I need for meaningful analytics?",
                answer: "The Edge Report requires 30 trades minimum. For statistically significant patterns, 100+ trades is ideal. Monte Carlo simulation and consistency scoring become more reliable with larger samples. Import as much history as you have."
            )
            faqItem(
                question: "Can I import from multiple platforms?",
                answer: "Yes. Every imported trade gets an ID derived from its details (platform, symbol, times, prices, size and the broker's own ID if there is one), so trades from different platforms never collide and re-importing the same file skips trades you already have."
            )
            faqItem(
                question: "Is my data sent anywhere?",
                answer: "Only if you turn on the optional features. AI Analysis (off by default) sends summary statistics, not individual trades, to Anthropic when you click \"Run Analysis\", using your own API key. Market Data sends only ticker symbols to Finnhub, using your own key. There are no Greenwick servers and no telemetry."
            )
            faqItem(
                question: "Where is my data stored?",
                answer: "All trade data is stored locally on your Mac in an encrypted SQLite database at ~/Library/Application Support/Greenwick/Greenwick.sqlite. Its key, the number of its last save and your API keys are in the macOS Keychain (with App Lock on, the journal key is sealed with your password). Nothing is stored in the cloud."
            )
            faqItem(
                question: "Can I use Greenwick offline?",
                answer: "Yes. All analytics, journaling, and export features work offline. Only live quotes (Browse, Watchlist) and AI analysis need an internet connection."
            )
            faqItem(
                question: "What happens if I delete Greenwick?",
                answer: "Your trade database persists at ~/Library/Application Support/Greenwick/ even after deleting the app. Reinstalling Greenwick will pick up your existing data. To fully remove data, delete this folder manually."
            )
            faqItem(
                question: "How is the trade grade calculated?",
                answer: "Each trade is scored on 4 dimensions (25 points each): R-Multiple quality (higher R = better), Execution efficiency (MFE-to-MAE ratio), Timing discipline (session quality, prime hours), and Trade management (breakeven usage, duration). Grades: A (80+), B (65+), C (50+), D (35+), F (<35)."
            )
            faqItem(
                question: "Can I use Greenwick for crypto?",
                answer: "Greenwick is optimized for stock and equity day trading. You can import crypto trades, but session detection is US-market specific."
            )
        }
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.bodyText)
                .fontWeight(.semibold)
            Text(answer)
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Troubleshooting

struct HelpTroubleshooting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Troubleshooting")

            HelpSubtitle("Import Fails with Column Mismatch")
            HelpParagraph("This means the CSV file doesn't match the expected format for the selected platform. Check the Platform Import Guides section for your specific platform's export format.")

            HelpSubtitle("Import Fails with \"Unsupported encoding\"")
            HelpParagraph("The CSV file uses a character encoding Greenwick can't read. Open the file in a text editor (TextEdit, VS Code) and re-save it as UTF-8 encoding.")

            HelpSubtitle("No Trades Appear After Import")
            HelpBullet("Check the Journal filters — you may have a symbol, session, or date range filter active that hides the imported trades.")
            HelpBullet("Click \"All Symbols\", \"All Sessions\", and \"All Time\" to reset filters.")
            HelpBullet("The import may have been all duplicates if you imported the same file twice.")

            HelpSubtitle("Live Quotes Not Loading")
            HelpBullet("Check that your Finnhub API key is saved in Settings > Market Data, then click Test Connection.")
            HelpBullet("Ensure you have an internet connection.")
            HelpBullet("Quotes are only available on weekdays when US stock markets are open.")

            HelpSubtitle("AI Analysis Fails")
            HelpBullet("Check that \"Allow AI analysis\" is on and your Anthropic API key is saved in Settings > AI Analysis.")
            HelpBullet("Ensure you have at least 30 trades imported.")
            HelpBullet("Check your internet connection.")
            HelpBullet("If you see a rate limit error, wait a few minutes and try again.")

            HelpSubtitle("App Feels Slow with Many Trades")
            HelpParagraph("Greenwick is optimized for 10,000+ trades. If performance degrades, try narrowing the date range filter on the Dashboard. The LazyVStack rendering loads components as you scroll.")

            HelpSubtitle("Journal Couldn't Be Read")
            HelpParagraph("If Greenwick says it couldn't read your journal and started a new one, the file could not be decrypted (rare). The old file is kept, still encrypted, next to the new one as Greenwick.sqlite.unreadable-<date>; nothing is deleted. If you have a backup, restore it from Settings > Data > Restore Backup.")
            HelpParagraph("If the problem is the disk rather than the file (for example the disk is full or the Greenwick folder can't be read), Greenwick leaves the journal exactly where it is and says so. If it could open the journal but not save it, it stays open and the \"Database Issue\" message says your latest changes are only in memory. Free up disk space: Greenwick keeps the changes and tries again with your next change and when you unlock. If it still can't save when you quit, it asks first: Try Again, or Quit Anyway (which loses the unsaved changes). If Greenwick locks while it asks, it doesn't quit.")

            HelpSubtitle("\"Greenwick Is Already Open\"")
            HelpParagraph("Only one copy of Greenwick can have your journal open at a time, so two copies can't overwrite each other's changes. This works on your Mac's own disk; on a network or external drive that doesn't support file locks, Greenwick can't tell that another copy is running, so run only one copy there. If a second copy starts (for example an older copy left in Downloads), it opens nothing and shows \"Greenwick is already open\": click \"Switch to It\" or quit the other copy first.")

            HelpSubtitle("Need More Help?")
            HelpParagraph("Open an issue on the project's GitHub page with your Greenwick version and the steps to reproduce. Never attach real trade data or API keys.")
        }
    }
}
