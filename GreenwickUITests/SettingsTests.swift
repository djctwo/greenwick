import XCTest

/// Settings: sections, opt-in AI defaults, and the sample-data / delete-all controls.
final class SettingsTests: GreenwickUITestCase {

    @MainActor
    func testSectionsAndFreeLicense() throws {
        let app = launchApp()
        open("Settings", in: app)
        for section in ["Security", "AI Analysis", "Market Data", "Data", "About"] {
            XCTAssertTrue(reveal(text(section, in: app), in: app), "Section '\(section)' should be in Settings")
        }
        XCTAssertTrue(reveal(text("GNU GPL v3, free and open source", in: app), in: app),
                      "About should state the free licence")
        assertNoPaywall(in: app, on: "Settings")
    }

    @MainActor
    func testAIAnalysisIsOffAndHasNoKeyByDefault() throws {
        let app = launchApp()
        open("Settings", in: app)
        // A checkbox or a switch depending on the macOS version; value 0 = off
        let toggle = app.descendants(matching: .any).matching(identifier: "settings.aiEnabled").firstMatch
        XCTAssertTrue(reveal(toggle, in: app), "AI opt-in switch should be in Settings")
        XCTAssertEqual("\(toggle.value ?? "nil")", "0", "AI analysis must be off by default")
        // First secure field on the page = the Anthropic key (the Finnhub key is further down)
        XCTAssertTrue(text("Your Anthropic API Key", in: app).exists, "Anthropic key row should be in Settings")
        let keyField = app.secureTextFields.firstMatch
        XCTAssertTrue(keyField.waitForExistence(timeout: 3), "Anthropic key field should be in Settings")
        XCTAssertEqual(keyField.value as? String ?? "", "", "No Anthropic key should be stored")
        XCTAssertTrue(app.buttons["settings.testConnection"].exists)
        XCTAssertFalse(app.buttons["settings.testConnection"].isEnabled,
                       "Market data Test Connection needs your own Finnhub key first")
        XCTAssertTrue(text("Stored securely in macOS Keychain", in: app).exists)
    }

    @MainActor
    func testLoadSampleDataThenCancelDeleteAll() throws {
        let app = launchApp()
        open("Settings", in: app)
        let deleteAll = app.buttons["settings.deleteAllTrades"]
        XCTAssertTrue(reveal(deleteAll, in: app))
        XCTAssertFalse(deleteAll.isEnabled, "Delete All Trades should be disabled on an empty journal")

        loadSampleData(in: app)
        // Loading again adds nothing
        let load = app.buttons["settings.loadSampleTrades"]
        XCTAssertTrue(reveal(load, in: app))
        load.click()
        XCTAssertTrue(text("Sample trades are already loaded", in: app).waitForExistence(timeout: 5),
                      "A second load must not duplicate the sample trades")
        XCTAssertTrue(text("\(Sample.tradeCount)", in: app).exists, "Imported Trades should read 30")

        XCTAssertTrue(reveal(deleteAll, in: app))
        XCTAssertTrue(deleteAll.isEnabled)
        deleteAll.click()
        let message = text(containing: "This will delete all \(Sample.tradeCount) imported trades", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Delete All should ask for confirmation")
        let cancel = buttonLabeled("Cancel", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))

        open("Journal", in: app)
        assertShows(["\(Sample.tradeCount) trades"], in: app, on: "Journal after cancelling Delete All")
    }

    @MainActor
    func testRemoveSampleTradesEmptiesASampleOnlyJournal() throws {
        let app = launchApp()
        loadSampleData(in: app)
        let remove = app.buttons["settings.removeSampleTrades"]
        XCTAssertTrue(reveal(remove, in: app), "Remove Sample Trades should be in Settings")
        remove.click()
        XCTAssertTrue(text("Removed \(Sample.tradeCount) sample trades", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text("0", in: app).exists, "Imported Trades should read 0")
        snapshot("settings-sample-removed", of: app)
    }

    /// Back Up Journal: password protection is offered (off by default without App Lock),
    /// the plain-backup warning shows, and mismatched passwords are refused before any
    /// file panel opens
    @MainActor
    func testBackUpJournalOffersPasswordProtection() throws {
        let app = launchApp()
        open("Settings", in: app)
        let backUp = app.buttons["settings.backUpJournal"]
        XCTAssertTrue(reveal(backUp, in: app), "Back Up Journal should be in Settings")
        XCTAssertTrue(reveal(text(containing: "Backups without a password are readable by anyone", in: app), in: app))
        backUp.click()

        XCTAssertTrue(text("Back Up Journal", in: app).waitForExistence(timeout: 5), "The backup options should open")
        let protect = app.descendants(matching: .any).matching(identifier: "backup.protect").firstMatch
        XCTAssertTrue(protect.waitForExistence(timeout: 3))
        XCTAssertEqual("\(protect.value ?? "nil")", "0", "Off by default when App Lock is off")
        XCTAssertTrue(text(containing: "readable by anyone who gets the file", in: app).exists,
                      "A plain backup must say it is readable by anyone")
        snapshot("backup-options-plain", of: app)

        protect.click()
        let fields = app.secureTextFields
        let password = fields.matching(NSPredicate(
            format: "label == %@ OR placeholderValue == %@", "Backup Password", "Backup Password")).firstMatch
        let confirm = fields.matching(NSPredicate(
            format: "label == %@ OR placeholderValue == %@", "Confirm Password", "Confirm Password")).firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 3), "Password fields appear with protection on")
        password.click()
        password.typeText("backup-pass-1")
        confirm.click()
        confirm.typeText("backup-pass-2")
        app.buttons["backup.submit"].click()
        XCTAssertTrue(text("Passwords do not match.", in: app).waitForExistence(timeout: 5),
                      "Mismatched passwords must be refused")
        snapshot("backup-options-protected", of: app)

        buttonLabeled("Cancel", in: app).click()
        // Not the "Back Up Journal" text: the Settings button has the same label and stays
        XCTAssertTrue(protect.waitForNonExistence(timeout: 5), "Cancel should close the backup options")
    }
}
