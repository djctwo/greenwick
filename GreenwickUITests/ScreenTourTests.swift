import XCTest

/// Loads the fictional sample trades and walks every main screen: each one must show
/// its own content, no billing or price text, and optional online features must ask for
/// the user's own key. Every screen is attached to the result as a screenshot; CI exports
/// them (plus a manifest) as the `Greenwick-ui-tests` artifact.
final class ScreenTourTests: GreenwickUITestCase {

    @MainActor
    func testWalkEveryScreenWithSampleData() throws {
        let app = launchApp()
        snapshot("01-journal-empty", of: app)

        loadSampleData(in: app)
        snapshot("02-settings-sample-loaded", of: app)

        let screens: [(tab: String, shot: String, markers: [String])] = [
            ("Journal", "03-journal", ["\(Sample.tradeCount) trades", Sample.totalPnL]),
            ("Dashboard", "04-dashboard", ["Total P&L: \(Sample.totalPnL), \(Sample.tradeCount) trades"]),
            ("Analytics", "05-analytics", ["Timing, Option 1"]),
            ("Browse", "06-browse", ["Finnhub API Key Required"]),
            ("Watchlist", "07-watchlist", ["No symbols on your watchlist"]),
            ("Edge Report", "08-edge-report", ["Total P&L: \(Sample.totalPnL), \(Sample.tradeCount) trades analyzed",
                                                "AI Recommendations (optional)"]),
            ("Import", "09-import", ["Drop CSV Trade Export Here"]),
            ("Settings", "10-settings", ["Security", "AI Analysis"]),
        ]
        for screen in screens {
            open(screen.tab, in: app)
            for marker in screen.markers {
                let found = text(marker, in: app).waitForExistence(timeout: 5)
                    || button(containing: marker, in: app).exists
                XCTAssertTrue(found, "\(screen.tab) should show '\(marker)'")
            }
            XCTAssertEqual(app.state, .runningForeground, "\(screen.tab) should not crash the app")
            // Analytics tips may say "save ~$120.00/month", so only billing words are checked there
            assertNoPaywall(in: app, on: screen.tab, checkPrices: screen.tab != "Analytics")
            snapshot(screen.shot, of: app)
        }

        // Analytics categories
        open("Analytics", in: app)
        let categories = ["timing", "sessions", "symbols", "risk", "behavioral", "advanced"]
        for (index, category) in categories.enumerated() {
            app.typeKey("\(index + 1)", modifierFlags: .option)
            let pill = app.buttons["\(category.capitalized), Option \(index + 1)"]
            XCTAssertTrue(waitUntil(timeout: 5) { pill.isSelected }, "Option+\(index + 1) should select \(category)")
            XCTAssertFalse(text("No Data Yet", in: app).exists)
            if category == "risk" {
                // Monthly Returns lists the year: "2026", never "2,026"
                // (the sample trades span the last 28 days, so early January also shows last year)
                let thisYear = Calendar.current.component(.year, from: Date())
                let listed = text(String(thisYear), in: app).waitForExistence(timeout: 5)
                    || text(String(thisYear - 1), in: app).exists
                XCTAssertTrue(listed, "Monthly Returns should list the year")
                let grouped = app.staticTexts.matching(NSPredicate(format: "value MATCHES %@", "[12],[0-9]{3}"))
                XCTAssertEqual(grouped.count, 0, "A year is shown with a thousands separator")
            }
            assertNoPaywall(in: app, on: "Analytics > \(category)", checkPrices: false)
            snapshot("11-analytics-\(index + 1)-\(category)", of: app)
        }

        // Optional market data and AI both point to the user's own key
        open("Browse", in: app)
        XCTAssertTrue(text("Then add your key in Settings > Market Data.", in: app).waitForExistence(timeout: 5))
        open("Edge Report", in: app)
        XCTAssertTrue(text(containing: "Add your own Anthropic API key", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(button(containing: "Run Analysis", in: app).exists)

        // Add Trade sheet and Help window
        open("Journal", in: app)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.buttons["addTrade.save"].waitForExistence(timeout: 5))
        snapshot("12-add-trade", of: app)
        app.buttons["addTrade.cancel"].click()
        XCTAssertTrue(app.buttons["addTrade.save"].waitForNonExistence(timeout: 3))

        let help = openHelpWindow(in: app)
        XCTAssertTrue(help.waitForExistence(timeout: 5), "Help > Greenwick Help should open Help")
        assertNoPaywall(in: app, on: "Help")
        if help.exists {
            let shot = XCTAttachment(screenshot: help.screenshot())
            shot.name = "13-help"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
