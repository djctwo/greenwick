import XCTest

/// Sidebar and keyboard navigation on an empty journal. Each check looks for content
/// that only exists on the target screen.
final class NavigationTests: GreenwickUITestCase {

    /// Each sidebar tab and a piece of text only that screen shows when the journal is empty.
    private let emptyScreens: [(tab: String, marker: String)] = [
        ("Journal", "No Trades Yet"),
        ("Dashboard", "No Data Yet"),
        ("Analytics", "No Data Yet"),
        ("Browse", "Finnhub API Key Required"),
        ("Watchlist", "No symbols on your watchlist"),
        ("Edge Report", "Need More Data"),
        ("Import", "Drop CSV Trade Export Here"),
        ("Settings", "Security"),
    ]

    @MainActor
    func testEverySidebarTabOpensItsScreen() throws {
        let app = launchApp()
        for screen in emptyScreens {
            open(screen.tab, in: app)
            XCTAssertTrue(text(screen.marker, in: app).waitForExistence(timeout: 5),
                          "\(screen.tab) should show '\(screen.marker)'")
            XCTAssertEqual(app.state, .runningForeground, "\(screen.tab) should not crash the app")
        }
    }

    @MainActor
    func testKeyboardShortcutsNavigate() throws {
        let app = launchApp()
        let shortcuts: [(key: String, marker: String)] = [
            ("2", "No Data Yet"),
            ("4", "Need More Data"),
            ("5", "Drop CSV Trade Export Here"),
            (",", "Security"),
            ("1", "No Trades Yet"),
        ]
        for shortcut in shortcuts {
            app.typeKey(shortcut.key, modifierFlags: .command)
            XCTAssertTrue(text(shortcut.marker, in: app).waitForExistence(timeout: 5),
                          "Cmd+\(shortcut.key) should show '\(shortcut.marker)'")
        }
    }

    @MainActor
    func testEmptyJournalAndDashboardPointToImport() throws {
        let app = launchApp()
        for tab in ["Journal", "Dashboard"] {
            open(tab, in: app)
            let goToImport = app.buttons["Go to Import"]
            XCTAssertTrue(goToImport.waitForExistence(timeout: 5), "\(tab) empty state should offer Go to Import")
            goToImport.click()
            XCTAssertTrue(app.buttons["import.chooseFile"].waitForExistence(timeout: 5),
                          "Go to Import on \(tab) should open the Import screen")
        }
    }

    @MainActor
    func testHelpWindowOpens() throws {
        let app = launchApp()
        let help = openHelpWindow(in: app)
        XCTAssertTrue(help.waitForExistence(timeout: 5), "Help > Greenwick Help should open the Help window")
        assertNoPaywall(in: app, on: "Help")
    }
}
