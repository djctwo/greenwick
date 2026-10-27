import XCTest

// MARK: - Paths

/// Where UI tests tell the app to keep its data.
///
/// The UI-test runner is sandboxed, so its NSTemporaryDirectory() is inside the runner's
/// own container (~/Library/Containers/...). Pointing the (unsandboxed) app there makes
/// macOS ask "Greenwick would like to access data from other apps". Use a plain folder
/// outside any container instead: `GREENWICK_UITEST_ROOT` if set (CI sets it through
/// `TEST_RUNNER_GREENWICK_UITEST_ROOT`), else /tmp.
enum UITestPaths {
    static var scratchRoot: String {
        if let root = ProcessInfo.processInfo.environment["GREENWICK_UITEST_ROOT"], !root.isEmpty {
            return root
        }
        return "/tmp"
    }
}

// MARK: - Sandbox

/// One throwaway "install": a private data folder and a private Keychain service.
/// Relaunching with the same sandbox reopens the same journal (used by the lock test).
struct UITestSandbox {
    let dataDirectory: String
    let keychainService: String

    static func fresh() -> UITestSandbox {
        let id = UUID().uuidString
        return UITestSandbox(
            dataDirectory: UITestPaths.scratchRoot + "/greenwick-uitests/\(id)",
            keychainService: "greenwick-uitests.\(id)"
        )
    }
}

// MARK: - Base Test Case

/// Shared launch and lookup helpers. Every test launches its own app instance with a
/// fresh sandbox and waits for the main window before touching anything.
class GreenwickUITestCase: XCTestCase {

    /// Sample data loaded by Load Sample Trades (`DemoDataGenerator`):
    /// 30 trades, 20 wins (+$3,305) / 10 losses (-$1,330), net +$1,975.00.
    enum Sample {
        static let tradeCount = 30
        static let totalPnL = "$1,975.00"
        static let winRate = "66.7%"
        static let winsLosses = "20W / 10L"
        static let profitFactor = "2.48"   // 3305 / 1330
        static let grossProfit = "$3.3K"
        static let expectancy = "$65.83"   // 1975 / 30
    }

    // MARK: Launch

    enum LaunchMode {
        /// `--uitesting`: skip the welcome screen (most tests)
        case skipWelcome
        /// `--uitesting-first-launch`: welcome screen as on a brand-new install
        case firstLaunch
        /// No test flags: exactly what a user's launch does
        case normal
    }

    /// Launch Greenwick in `sandbox` and wait for its window.
    /// - Parameter expectMainWindow: also wait until the sidebar is on screen (the normal case).
    @MainActor
    @discardableResult
    func launchApp(
        sandbox: UITestSandbox = .fresh(),
        mode: LaunchMode = .skipWelcome,
        expectMainWindow: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GREENWICK_DATA_DIR"] = sandbox.dataDirectory
        app.launchEnvironment["GREENWICK_KEYCHAIN_SERVICE"] = sandbox.keychainService
        // Order matters: AppKit reads "-key value" pairs from the arguments as defaults, and
        // a "--flag" followed by another argument would swallow it as its value. So defaults
        // pairs go first and the bare flag last.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        switch mode {
        case .skipWelcome: app.launchArguments.append("--uitesting")
        case .firstLaunch: app.launchArguments.append("--uitesting-first-launch")
        case .normal: break
        }
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20),
                      "Greenwick should open a window", file: file, line: line)
        if expectMainWindow {
            XCTAssertTrue(app.buttons["sidebar.Journal"].waitForExistence(timeout: 15),
                          "Main window (sidebar) should be showing", file: file, line: line)
        }
        return app
    }

    // MARK: Navigation

    @MainActor
    func open(_ tab: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["sidebar.\(tab)"]
        guard button.waitForExistence(timeout: 5) else {
            XCTFail("Sidebar tab '\(tab)' not found", file: file, line: line)
            return
        }
        button.click()
    }

    /// Help > Greenwick Help. (Pressing Cmd+? opens the system's Help-menu search
    /// instead, so the test uses the menu like a mouse user would.)
    @MainActor
    func openHelpWindow(in app: XCUIApplication) -> XCUIElement {
        let helpMenu = app.menuBarItems["Help"]
        helpMenu.click()
        // Scoped to the Help menu: the Window menu lists the Help window too
        let item = helpMenu.menuItems["Greenwick Help"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Help menu should list Greenwick Help")
        item.click()
        return app.windows["Greenwick Help"]
    }

    /// Settings > Data > Load Sample Trades, then wait for Settings to confirm 30 were added.
    @MainActor
    func loadSampleData(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        open("Settings", in: app, file: file, line: line)
        let load = app.buttons["settings.loadSampleTrades"]
        guard reveal(load, in: app) else {
            XCTFail("Load Sample Trades button not found in Settings", file: file, line: line)
            return
        }
        XCTAssertTrue(load.isEnabled, "Load Sample Trades should be enabled", file: file, line: line)
        load.click()
        XCTAssertTrue(text("Added \(Sample.tradeCount) fictional sample trades", in: app).waitForExistence(timeout: 10),
                      "Settings should confirm the sample trades were loaded", file: file, line: line)
    }

    /// Scroll the detail pane until `element` exists and is hittable (SwiftUI forms create
    /// rows lazily, so controls further down may not exist until scrolled into view).
    @MainActor
    @discardableResult
    func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }
        // A point in the detail pane (right of the sidebar), scrolled down then back up
        let detailPane = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        for deltaY in Array(repeating: -250.0, count: 10) + Array(repeating: 250.0, count: 20) {
            detailPane.scroll(byDeltaX: 0, deltaY: deltaY)
            if element.waitForExistence(timeout: 0.5), element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    @MainActor
    @discardableResult
    func reveal(_ match: TextMatch, in app: XCUIApplication) -> Bool {
        if match.waitForExistence(timeout: 3) { return reveal(match.element, in: app) }
        let detailPane = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        for deltaY in Array(repeating: -250.0, count: 10) + Array(repeating: 250.0, count: 20) {
            detailPane.scroll(byDeltaX: 0, deltaY: deltaY)
            if match.waitForExistence(timeout: 0.5) { return reveal(match.element, in: app) }
        }
        return false
    }

    /// Poll `condition` until it is true or `timeout` passes.
    @MainActor
    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return condition()
    }

    // MARK: Lookup

    /// Text shown exactly as `string`. SwiftUI Text on macOS exposes its string as a static
    /// text's value; Form section headers and combined elements (KPI cards: "Title: value,
    /// subtitle") expose it as a label. Labels are matched across all element types: on the
    /// macOS 15 runners a `staticTexts` query filtered on label misses section headers.
    @MainActor
    func text(_ string: String, in app: XCUIApplication) -> TextMatch {
        TextMatch(candidates: [
            app.staticTexts.matching(NSPredicate(format: "value == %@", string)).firstMatch,
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", string)).firstMatch,
        ])
    }

    /// Text that contains `string` (see `text(_:in:)`).
    @MainActor
    func text(containing string: String, in app: XCUIApplication) -> TextMatch {
        TextMatch(candidates: [
            app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", string)).firstMatch,
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", string)).firstMatch,
        ])
    }

    /// A button whose label contains `string`.
    @MainActor
    func button(containing string: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", string)).firstMatch
    }

    /// A button whose label is exactly `string` (alert buttons have no identifier).
    @MainActor
    func buttonLabeled(_ string: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", string)).firstMatch
    }

    @MainActor
    func assertShows(_ strings: [String], in app: XCUIApplication, on screen: String,
                     timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        for string in strings {
            XCTAssertTrue(text(string, in: app).waitForExistence(timeout: timeout),
                          "'\(string)' should be shown on \(screen)", file: file, line: line)
        }
    }

    // MARK: No paywall

    /// Words that would mean billing UI crept back in (whole-word "Pro", case-sensitive, so
    /// "Profit" and "Prop firm" don't count).
    static let paywallPattern =
        "(?s).*((?i:upgrade|\\btrial\\b|subscribe|subscription|purchase|premium|buy now|license key|per month|per year)|\\bPro\\b|\\bPRO\\b).*"

    /// A price with a billing period, e.g. "$9.99/mo" or "$49 per year". Not checked on
    /// Analytics, whose tips legitimately say things like "save ~$120.00/month".
    static let pricePattern =
        "(?s).*\\$\\s?\\d+(\\.\\d{2})?\\s?(/|per |a )(mo|month|yr|year)\\b.*"

    @MainActor
    func assertNoPaywall(in app: XCUIApplication, on screen: String, checkPrices: Bool = true,
                         file: StaticString = #filePath, line: UInt = #line) {
        var patterns = [Self.paywallPattern]
        if checkPrices { patterns.append(Self.pricePattern) }
        for pattern in patterns {
            let byValue = app.staticTexts.matching(NSPredicate(format: "value MATCHES %@", pattern))
            let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern))
            let found = byValue.allElementsBoundByIndex.map { "\($0.value ?? "")" }
                + byLabel.allElementsBoundByIndex.map(\.label)
            XCTAssertTrue(found.isEmpty, "Billing/price text on \(screen): \(found)", file: file, line: line)
        }
    }

    // MARK: Screenshots

    /// Attach a screenshot of the front window to the test result (CI exports them).
    @MainActor
    func snapshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Text match

/// A text that may be exposed through either its value or its label. Queried separately:
/// one predicate over both attributes misses elements that have no value at all.
@MainActor
struct TextMatch {
    let candidates: [XCUIElement]

    var exists: Bool { candidates.contains { $0.exists } }

    /// The candidate that exists (or the first one, for error messages)
    var element: XCUIElement { candidates.first { $0.exists } ?? candidates[0] }

    func waitForExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return exists
    }

    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if !exists { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return !exists
    }
}
