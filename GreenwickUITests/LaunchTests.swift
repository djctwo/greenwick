import XCTest

/// First launch (welcome screen) and the app lock. Both relaunch the app on the same
/// data folder and Keychain service to check that state survives a restart.
final class LaunchTests: GreenwickUITestCase {

    // MARK: - Welcome screen

    @MainActor
    func testFirstLaunchShowsWelcomeOnce() throws {
        let sandbox = UITestSandbox.fresh()
        var app = launchApp(sandbox: sandbox, mode: .firstLaunch, expectMainWindow: false)

        XCTAssertTrue(text("Welcome to Greenwick", in: app).waitForExistence(timeout: 10),
                      "A first launch should show the welcome screen")
        XCTAssertFalse(app.buttons["sidebar.Journal"].exists, "The journal should wait until Get Started")
        assertNoPaywall(in: app, on: "Welcome")
        snapshot("welcome", of: app)

        let getStarted = button(containing: "Get Started", in: app)
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.click()
        XCTAssertTrue(app.buttons["sidebar.Journal"].waitForExistence(timeout: 10),
                      "Get Started should open the journal")

        // A normal launch afterwards (no test flags) goes straight to the journal
        app.terminate()
        app = launchApp(sandbox: sandbox, mode: .normal)
        XCTAssertFalse(text("Welcome to Greenwick", in: app).exists, "Welcome should only show once")
    }

    @MainActor
    func testWelcomeScreenLoadsFictionalSampleTrades() throws {
        let app = launchApp(mode: .firstLaunch, expectMainWindow: false)
        XCTAssertTrue(text("Welcome to Greenwick", in: app).waitForExistence(timeout: 10))

        let load = app.buttons["onboarding.loadSampleTrades"]
        XCTAssertTrue(load.waitForExistence(timeout: 5), "The welcome screen should offer sample trades")
        load.click()
        XCTAssertTrue(text("Load Sample Trades?", in: app).waitForExistence(timeout: 5),
                      "Loading should ask for confirmation")
        XCTAssertTrue(text(containing: "fictional", in: app).exists,
                      "The confirmation should say the trades are fictional")
        snapshot("welcome-sample-confirm", of: app)
        buttonLabeled("Load", in: app).click()

        XCTAssertTrue(app.buttons["sidebar.Journal"].waitForExistence(timeout: 10),
                      "Loading sample trades should continue into the journal")
        open("Journal", in: app)
        assertShows(["\(Sample.tradeCount) trades", Sample.totalPnL], in: app, on: "Journal with sample trades")
    }

    // MARK: - App lock

    private let password = "correct-horse-42"

    @MainActor
    func testAppLockSurvivesRestartAndUnlocks() throws {
        let sandbox = UITestSandbox.fresh()
        var app = launchApp(sandbox: sandbox)
        loadSampleData(in: app)
        enableAppLock(in: app)

        // Quit, then start again: the journal on disk is encrypted with a key only the
        // password unwraps, so the lock screen comes up before anything is decrypted
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Cmd+Q should quit Greenwick")
        app = launchApp(sandbox: sandbox, expectMainWindow: false)

        XCTAssertTrue(text("Greenwick is Locked", in: app).waitForExistence(timeout: 10),
                      "With app lock on, a restart should show the lock screen")
        XCTAssertFalse(app.buttons["sidebar.Journal"].exists, "The journal must stay hidden while locked")
        snapshot("lock-screen", of: app)

        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let unlock = buttonLabeled("Unlock", in: app)
        XCTAssertFalse(unlock.isEnabled, "Unlock should be disabled with no password typed")

        field.click()
        field.typeText("wrong-password\r")
        XCTAssertTrue(text("Incorrect password (1/5)", in: app).waitForExistence(timeout: 10),
                      "A wrong password should be rejected and counted")
        XCTAssertFalse(app.buttons["sidebar.Journal"].exists)

        field.click()
        field.typeText(password + "\r")
        XCTAssertTrue(app.buttons["sidebar.Journal"].waitForExistence(timeout: 20),
                      "The right password should unlock Greenwick")

        // The journal decrypted intact after the restart
        open("Journal", in: app)
        assertShows(["\(Sample.tradeCount) trades", Sample.totalPnL], in: app, on: "Journal after unlocking")
    }

    @MainActor
    func testForgotPasswordNeverUnlocksWithoutConfirmation() throws {
        let sandbox = UITestSandbox.fresh()
        var app = launchApp(sandbox: sandbox)
        enableAppLock(in: app)
        app.terminate()
        app = launchApp(sandbox: sandbox, expectMainWindow: false)
        XCTAssertTrue(text("Greenwick is Locked", in: app).waitForExistence(timeout: 10))

        let forgot = buttonLabeled("Forgot Password?", in: app)
        XCTAssertTrue(forgot.waitForExistence(timeout: 5))
        forgot.click()
        // Signed builds keep a Touch ID / Mac password recovery copy of the journal key
        // ("Reset App Lock?", then a system prompt not driven here). Ad-hoc builds such as
        // CI's can't, so the only way out is erasing local data. Either way, Cancel must
        // leave the journal locked.
        let reset = text("Reset App Lock?", in: app)
        let erase = text("Erase Greenwick Data?", in: app)
        XCTAssertTrue(waitUntil(timeout: 5) { reset.exists || erase.exists },
                      "Forgot Password should explain what happens next")
        if reset.exists {
            XCTAssertTrue(text(containing: "confirm with your Mac login password", in: app).exists)
        } else {
            XCTAssertTrue(text(containing: "can't use Touch ID or your Mac password", in: app).exists)
            snapshot("lock-forgot-erase", of: app)
        }
        buttonLabeled("Cancel", in: app).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !reset.exists && !erase.exists })
        XCTAssertTrue(text("Greenwick is Locked", in: app).exists, "Cancel must leave the app locked")
        XCTAssertFalse(app.buttons["sidebar.Journal"].exists)
    }

    @MainActor
    func testTurningTheLockOffNeedsThePassword() throws {
        let app = launchApp()
        enableAppLock(in: app)

        button(containing: "Disable App Lock", in: app).click()
        XCTAssertTrue(text("Disable App Lock", in: app).waitForExistence(timeout: 5))
        let current = app.secureTextFields.matching(NSPredicate(
            format: "label == %@ OR placeholderValue == %@", "Current Password", "Current Password")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        current.click()
        current.typeText("wrong-password")
        buttonLabeled("Disable Lock", in: app).click()
        XCTAssertTrue(text("Incorrect password.", in: app).waitForExistence(timeout: 10),
                      "A wrong password must not turn the lock off")

        current.click()
        current.typeKey("a", modifierFlags: .command)
        current.typeText(password)
        buttonLabeled("Disable Lock", in: app).click()
        XCTAssertTrue(button(containing: "Enable App Lock", in: app).waitForExistence(timeout: 10),
                      "The right password turns the lock off")
    }

    /// With App Lock on: "Lock after inactivity" (default 15 minutes) can be changed, and
    /// Back Up Journal starts with password protection on
    @MainActor
    func testAppLockOffersIdleLockAndProtectedBackups() throws {
        let app = launchApp()
        enableAppLock(in: app)

        let idle = app.popUpButtons["settings.idleLock"]
        XCTAssertTrue(reveal(idle, in: app), "Lock after inactivity should show with App Lock on")
        idle.click()
        for choice in ["Off", "1 minute", "5 minutes", "15 minutes", "30 minutes", "60 minutes"] {
            XCTAssertTrue(app.menuItems[choice].waitForExistence(timeout: 3), "Missing choice \(choice)")
        }
        app.menuItems["30 minutes"].click()
        XCTAssertEqual(idle.value as? String, "30 minutes")
        snapshot("settings-idle-lock", of: app)
        // Back to the default (preferences are shared between UI test runs)
        idle.click()
        app.menuItems["15 minutes"].click()
        XCTAssertEqual(idle.value as? String, "15 minutes")

        let backUp = app.buttons["settings.backUpJournal"]
        XCTAssertTrue(reveal(backUp, in: app))
        backUp.click()
        let protect = app.descendants(matching: .any).matching(identifier: "backup.protect").firstMatch
        XCTAssertTrue(protect.waitForExistence(timeout: 5))
        XCTAssertEqual("\(protect.value ?? "nil")", "1", "On by default when App Lock is on")
        buttonLabeled("Cancel", in: app).click()
    }

    /// Settings > Security > Enable App Lock with `password`.
    @MainActor
    private func enableAppLock(in app: XCUIApplication) {
        open("Settings", in: app)
        let enable = button(containing: "Enable App Lock", in: app)
        XCTAssertTrue(reveal(enable, in: app), "Enable App Lock should be in Settings")
        enable.click()
        XCTAssertTrue(text("Set App Lock Password", in: app).waitForExistence(timeout: 5))

        let fields = app.secureTextFields
        let newPassword = fields.matching(NSPredicate(
            format: "label == %@ OR placeholderValue == %@", "New Password", "New Password")).firstMatch
        let confirm = fields.matching(NSPredicate(
            format: "label == %@ OR placeholderValue == %@", "Confirm Password", "Confirm Password")).firstMatch
        XCTAssertTrue(newPassword.waitForExistence(timeout: 3))
        newPassword.click()
        newPassword.typeText(password)
        confirm.click()
        confirm.typeText(password)
        buttonLabeled("Set Password", in: app).click()

        // Wrapping the journal key (PBKDF2, 600,000 rounds) takes a moment
        XCTAssertTrue(text("Set App Lock Password", in: app).waitForNonExistence(timeout: 15),
                      "Setting a valid password should close the sheet")
        XCTAssertTrue(button(containing: "Disable App Lock", in: app).waitForExistence(timeout: 5),
                      "Settings should now show the lock as enabled")
    }
}
