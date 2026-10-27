import XCTest

/// Trade journal: the sample trades, and adding a trade by hand.
final class JournalTests: GreenwickUITestCase {

    @MainActor
    func testJournalListsSampleTrades() throws {
        let app = launchApp()
        loadSampleData(in: app)
        open("Journal", in: app)
        assertShows(["\(Sample.tradeCount) trades", Sample.totalPnL], in: app, on: "Journal")
        for symbol in ["AAPL", "NVDA", "TSLA"] {
            XCTAssertTrue(text(symbol, in: app).waitForExistence(timeout: 3), "\(symbol) row should be listed")
        }
    }

    @MainActor
    func testCmdNOpensAddTradeOnEmptyJournal() throws {
        let app = launchApp()
        XCTAssertTrue(text("No Trades Yet", in: app).waitForExistence(timeout: 5))
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.buttons["addTrade.save"].waitForExistence(timeout: 5), "Cmd+N should open Add Trade")
        XCTAssertFalse(app.buttons["addTrade.save"].isEnabled, "Save should be disabled on an empty form")
        app.buttons["addTrade.cancel"].click()
        XCTAssertTrue(app.buttons["addTrade.save"].waitForNonExistence(timeout: 3), "Cancel should close the sheet")
        XCTAssertTrue(text("No Trades Yet", in: app).exists, "Cancel should not add a trade")
    }

    @MainActor
    func testAddTradeValidatesPreviewsAndSaves() throws {
        let app = launchApp()
        loadSampleData(in: app)
        open("Journal", in: app)
        let addTrade = app.buttons["journal.addTrade"]
        XCTAssertTrue(addTrade.waitForExistence(timeout: 5))
        addTrade.click()

        let save = app.buttons["addTrade.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save should be disabled until the required fields are filled")

        type("ibm", into: "addTrade.symbol", in: app)
        type("50", into: "addTrade.shares", in: app)
        type("420.00", into: "addTrade.openPrice", in: app)
        XCTAssertFalse(save.isEnabled, "Save should stay disabled without a close price")
        type("425.50", into: "addTrade.closePrice", in: app)

        // Symbol is upper-cased as you type; buy 50 x (425.50 - 420.00) = +$275.00
        XCTAssertEqual(app.textFields["addTrade.symbol"].value as? String, "IBM")
        XCTAssertTrue(text("+$275.00", in: app).waitForExistence(timeout: 3), "P&L preview should be +$275.00")
        XCTAssertTrue(save.isEnabled, "Save should be enabled once the form is complete")
        save.click()

        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "Saving should close the sheet")
        assertShows(["\(Sample.tradeCount + 1) trades", "$2,250.00"], in: app, on: "Journal after adding a trade")
        XCTAssertTrue(text("IBM", in: app).waitForExistence(timeout: 3), "The new IBM trade should be listed")
    }

    @MainActor
    private func type(_ string: String, into identifier: String, in app: XCUIApplication) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Field \(identifier) should exist")
        field.click()
        field.typeText(string)
    }
}
