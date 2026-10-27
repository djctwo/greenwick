import XCTest
@testable import Greenwick

/// Database writes, data-folder isolation, and what the optional AI feature would send.
final class StorageAndPrivacyTests: XCTestCase {

    // MARK: - Repository

    private func makeRepository() throws -> (DatabaseManager, TradeRepository) {
        let db = try DatabaseManager(inMemory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: db.databasePath)
            try? FileManager.default.removeItem(atPath: db.databasePath + "-wal")
            try? FileManager.default.removeItem(atPath: db.databasePath + "-shm")
        }
        return (db, TradeRepository(database: db))
    }

    private func sampleTrades(count: Int) -> [Trade] {
        let template = DemoDataGenerator.generateTrades()[0]
        return (0..<count).map { i in
            var t = template
            t.ticket = Int64(1_000_000 + i)
            return t
        }
    }

    func testBulkInsertHandlesLargeImports() throws {
        let (_, repo) = try makeRepository()
        let trades = sampleTrades(count: 40_000)
        XCTAssertEqual(try repo.bulkInsert(trades), 40_000)
        XCTAssertEqual(try repo.count(), 40_000)
        // Re-importing the same batch inserts nothing
        XCTAssertEqual(try repo.bulkInsert(Array(trades.prefix(1_000))), 0)
    }

    func testBulkInsertSkipsDuplicateTicketsWithinOneBatch() throws {
        let (_, repo) = try makeRepository()
        let trades = sampleTrades(count: 3)
        XCTAssertEqual(try repo.bulkInsert(trades + trades), 3)
    }

    func testHostileTextIsStoredLiterally() throws {
        let (_, repo) = try makeRepository()
        var trade = sampleTrades(count: 1)[0]
        trade.symbol = "X'); DROP TABLE trades;--"
        XCTAssertEqual(try repo.bulkInsert([trade]), 1)
        let stored = try repo.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.symbol, trade.symbol)
        let id = try XCTUnwrap(stored.first?.id)
        try repo.updateNotes(tradeId: id, notes: "'; DELETE FROM trades; --")
        XCTAssertEqual(try repo.count(), 1)
    }

    func testEditingCostsMovesNetProfitByTheDifference() throws {
        let (_, repo) = try makeRepository()
        var trade = sampleTrades(count: 1)[0]
        trade.netProfit = 100
        trade.commission = 2
        trade.swap = 0
        XCTAssertEqual(try repo.bulkInsert([trade]), 1)
        let id = try XCTUnwrap(try repo.fetchAll().first?.id)
        try repo.updateCosts(tradeId: id, commission: 5, swap: 0)
        let updated = try XCTUnwrap(try repo.fetchAll().first)
        XCTAssertEqual(updated.netProfit, 97)
        XCTAssertEqual(updated.commission, 5)
        XCTAssertEqual(updated.grossProfitBeforeCosts, 102)
    }

    // MARK: - Data isolation

    func testTestsNeverUseTheReleaseDataFolderOrKeychainService() {
        let releaseFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Greenwick", isDirectory: true).standardizedFileURL.path
        XCTAssertNotEqual(AppPaths.dataDirectory.standardizedFileURL.path, releaseFolder)
        XCTAssertFalse(AppPaths.databaseURL.path.hasPrefix(releaseFolder + "/"))
        XCTAssertNotEqual(AppPaths.keychainService, AppPaths.productionBundleID)
    }

    func testKeychainServiceOverrideIsIgnoredByTheReleaseBuild() {
        let env = ["GREENWICK_KEYCHAIN_SERVICE": "somewhere-else"]
        // Release bundle ID: always its own service, whatever the environment says
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app", environment: env,
                                                isRunningUnitTests: false), "com.greenwick.app")
        // Test/dev builds may be pointed at a throwaway service (UI tests do this)
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app.ci", environment: env,
                                                isRunningUnitTests: false), "somewhere-else")
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app.ci", environment: [:],
                                                isRunningUnitTests: false), "com.greenwick.app.ci")
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app.ci", environment: ["GREENWICK_KEYCHAIN_SERVICE": ""],
                                                isRunningUnitTests: true), "com.greenwick.app.ci.unittests")
    }

    // MARK: - AI data minimisation

    func testAIPromptContainsOnlyAggregates() {
        var trades = DemoDataGenerator.generateTrades()
        for i in trades.indices {
            trades[i].notes = "PRIVATE-NOTE-\(i)"
            trades[i].tags = "private-tag"
            trades[i].comment = "PRIVATE-COMMENT"
            trades[i].screenshots = "secret.jpg"
        }
        let prompt = PromptBuilder.edgeAnalysis(from: trades, metrics: MetricsCalculator.calculate(from: trades))
        for secret in ["PRIVATE-NOTE", "private-tag", "PRIVATE-COMMENT", "secret.jpg", "\(trades[0].ticket)"] {
            XCTAssertFalse(prompt.contains(secret), "Prompt must not include \(secret)")
        }
    }

    func testAIIsOffByDefault() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Configuration.AI.enabledKey)
        defaults.removeObject(forKey: Configuration.AI.enabledKey)
        defer { defaults.set(previous, forKey: Configuration.AI.enabledKey) }
        XCTAssertFalse(Configuration.AI.isEnabled)
        XCTAssertFalse(Configuration.AI.isReady)
    }

    // MARK: - TLS pinning (live network, opt-in: GREENWICK_NETWORK_TESTS=1)

    func testPinnedHostsStillMatchPins() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GREENWICK_NETWORK_TESTS"] == "1",
                          "Set GREENWICK_NETWORK_TESTS=1 to run live TLS checks")
        let session = CertificatePinningDelegate.pinnedSession(timeout: 20)
        for host in ["https://finnhub.io/api/v1/quote?symbol=AAPL", "https://api.anthropic.com/v1/models"] {
            let (_, response) = try await session.data(from: try XCTUnwrap(URL(string: host)))
            // No key sent, so 401/403 is expected. A pin failure would throw instead.
            XCTAssertNotNil(response as? HTTPURLResponse, host)
        }
    }
}

/// Screenshot filenames come from the database (which a restored backup controls).
final class ScreenshotPathTests: XCTestCase {
    func testScreenshotFilenamesCannotEscapeTheirFolder() {
        let manager = ScreenshotManager.shared
        let dir = manager.screenshotDir(for: 42).standardizedFileURL.path
        for hostile in ["..", ".", "../../etc/passwd", "/etc/passwd", "a/../../b", ""] {
            // Rejected outright (nil); a name is never resolved outside the trade's folder
            if let url = manager.imageURL(filename: hostile, for: 42)?.standardizedFileURL.path {
                XCTFail("\(hostile) was accepted: \(url)")
            }
        }
        let own = "\(UUID().uuidString).jpg" // the only format the app writes
        let url = manager.imageURL(filename: own, for: 42)
        XCTAssertEqual(url?.lastPathComponent, own)
        XCTAssertTrue(url?.standardizedFileURL.path.hasPrefix(dir + "/") == true)
    }
}

/// Opt-in helper (not a check): writes the demo trades into the data folder given by
/// `TEST_RUNNER_GREENWICK_DATA_DIR`, for README screenshots. Run with
/// `TEST_RUNNER_GREENWICK_SEED_DEMO=1`.
final class DemoSeedHelper: XCTestCase {
    func testSeedDemoDatabase() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GREENWICK_SEED_DEMO"] == "1",
                          "Opt-in helper for screenshots")
        let path = AppPaths.databaseURL.path
        let encrypted = FileManager.default.fileExists(atPath: path) && !DatabaseEncryption.fileIsPlaintext(at: path)
        let db = try DatabaseManager(path: path, key: try AppLockVault.live.plainKey(createIfMissing: !encrypted),
                                     ledger: .live)
        defer { db.close() }
        var trades = DemoDataGenerator.generateTrades()
        // Optionally seed from a sample export instead (same parser path as the Import screen)
        if let file = ProcessInfo.processInfo.environment["GREENWICK_SEED_FILE"], !file.isEmpty {
            let detection = try GenericCSVParser.detect(fileAt: file)
            trades = try GenericCSVParser.parse(fileAt: file, mapping: try XCTUnwrap(detection.mapping))
        }
        let inserted = try TradeRepository(database: db).bulkInsert(trades)
        XCTAssertGreaterThan(inserted, 0)
    }
}
