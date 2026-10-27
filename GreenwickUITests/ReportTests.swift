import XCTest

/// Dashboard, Analytics and Edge Report with the sample trades: the headline numbers must
/// match what `DemoDataGenerator` produces, and optional AI must ask for the user's own key.
final class ReportTests: GreenwickUITestCase {

    @MainActor
    func testDashboardShowsSampleNumbers() throws {
        let app = launchApp()
        loadSampleData(in: app)
        open("Dashboard", in: app)
        // Each KPI card reads as one element: "Title: value, subtitle"
        assertShows(["Total P&L: \(Sample.totalPnL), \(Sample.tradeCount) trades",
                     "Win Rate: \(Sample.winRate), \(Sample.winsLosses)",
                     "Profit Factor: \(Sample.profitFactor), Gross: \(Sample.grossProfit)",
                     "Expectancy: \(Sample.expectancy), per trade"],
                    in: app, on: "Dashboard")
        assertNoPaywall(in: app, on: "Dashboard")
    }

    @MainActor
    func testAnalyticsCategoriesSwitch() throws {
        let app = launchApp()
        loadSampleData(in: app)
        open("Analytics", in: app)
        let categories = ["Timing", "Sessions", "Symbols", "Risk", "Behavioral", "Advanced"]
        for (index, category) in categories.enumerated() {
            let pill = app.buttons["\(category), Option \(index + 1)"]
            XCTAssertTrue(pill.waitForExistence(timeout: 5), "\(category) pill should read '\(category), Option \(index + 1)'")
            app.typeKey("\(index + 1)", modifierFlags: .option)
            XCTAssertTrue(waitUntil(timeout: 5) { pill.isSelected },
                          "Option+\(index + 1) should select \(category)")
            XCTAssertFalse(text("No Data Yet", in: app).exists, "\(category) should show the sample trades")
            XCTAssertEqual(app.state, .runningForeground, "\(category) should not crash the app")
            assertNoPaywall(in: app, on: "Analytics > \(category)", checkPrices: false)
        }
    }

    @MainActor
    func testEdgeReportNeedsThirtyTrades() throws {
        let app = launchApp()
        open("Edge Report", in: app)
        assertShows(["Need More Data", "0 / 30 trades imported"], in: app, on: "empty Edge Report")
        XCTAssertFalse(app.buttons["edgeReport.openAISettings"].exists, "No AI card without enough trades")
    }

    @MainActor
    func testEdgeReportWithSampleDataAndOptionalAI() throws {
        let app = launchApp()
        loadSampleData(in: app)
        open("Edge Report", in: app)
        assertShows(["Total P&L: \(Sample.totalPnL), \(Sample.tradeCount) trades analyzed",
                     "Win Rate: \(Sample.winRate), \(Sample.winsLosses)",
                     "Profit Factor: \(Sample.profitFactor)",
                     "Expectancy: \(Sample.expectancy), per trade",
                     "By Session", "Where You Make Money", "Where You Lose Money"],
                    in: app, on: "Edge Report")

        // AI is optional, off by default, and asks for the user's own key
        XCTAssertTrue(text("AI Recommendations (optional)", in: app).exists)
        XCTAssertTrue(text(containing: "Add your own Anthropic API key", in: app).exists,
                      "AI card should ask for your own key")
        XCTAssertFalse(button(containing: "Run Analysis", in: app).exists,
                       "Run Analysis must not be offered without a key and the opt-in")
        assertNoPaywall(in: app, on: "Edge Report")

        let openSettings = app.buttons["edgeReport.openAISettings"]
        XCTAssertTrue(openSettings.exists, "AI card should link to Settings")
        openSettings.click()
        XCTAssertTrue(app.descendants(matching: .any)["settings.aiEnabled"].waitForExistence(timeout: 5),
                      "Open Settings should show the AI opt-in switch")
    }
}
