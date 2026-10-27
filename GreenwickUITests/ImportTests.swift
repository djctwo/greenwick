import XCTest

/// The Import screen: supported brokers, per-broker export steps, and the file picker.
/// (Parsing every broker format is covered by the unit tests.)
final class ImportTests: GreenwickUITestCase {

    private let platforms = [
        "Thinkorswim", "Webull", "Interactive Brokers", "TradingView", "NinjaTrader",
        "Robinhood", "Charles Schwab", "Fidelity", "E*Trade", "Tastytrade", "Generic CSV",
    ]

    @MainActor
    func testListsAllElevenPlatforms() throws {
        let app = launchApp()
        open("Import", in: app)
        XCTAssertTrue(text("Supported Platforms", in: app).waitForExistence(timeout: 5))
        for platform in platforms {
            XCTAssertTrue(button(containing: platform, in: app).waitForExistence(timeout: 3),
                          "Platform '\(platform)' should be listed")
        }
    }

    @MainActor
    func testPlatformExpandsToShowExportSteps() throws {
        let app = launchApp()
        open("Import", in: app)
        let schwab = button(containing: "Charles Schwab", in: app)
        XCTAssertTrue(schwab.waitForExistence(timeout: 5))
        let steps = text("Accounts → History → Export → CSV", in: app)
        XCTAssertFalse(steps.exists, "Export steps should be hidden until the platform is expanded")

        schwab.click()
        XCTAssertTrue(steps.waitForExistence(timeout: 3), "Expanding Schwab should show its export steps")
        XCTAssertTrue(text("Transaction History", in: app).exists)

        schwab.click()
        XCTAssertTrue(steps.waitForNonExistence(timeout: 3), "Clicking again should collapse it")
    }

    @MainActor
    func testChooseFileOpensAndCancelsFilePicker() throws {
        let app = launchApp()
        open("Import", in: app)
        let chooseFile = app.buttons["import.chooseFile"]
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.click()

        // fileImporter shows an NSOpenPanel, as a sheet on the main window or its own dialog
        let panelCancel = app.sheets.buttons["Cancel"].firstMatch
        let dialogCancel = app.dialogs.buttons["Cancel"].firstMatch
        let opened = panelCancel.waitForExistence(timeout: 10) || dialogCancel.waitForExistence(timeout: 2)
        XCTAssertTrue(opened, "Choose File should open a file picker")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        XCTAssertTrue(panelCancel.waitForNonExistence(timeout: 5) && !dialogCancel.exists,
                      "Escape should close the file picker")
        XCTAssertTrue(text("Drop CSV Trade Export Here", in: app).exists, "Still on Import, nothing imported")
    }
}
