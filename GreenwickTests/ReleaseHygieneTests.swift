import XCTest
@testable import Greenwick

/// Release builds must not be redirectable or debuggable by anyone who can launch them.
final class ReleaseHygieneTests: XCTestCase {

    func testReleaseBuildsIgnoreTheDataFolderOverride() {
        let env = ["GREENWICK_DATA_DIR": "/tmp/copied-journal"]
        let release = AppPaths.dataDirectory(bundleID: "com.greenwick.app", environment: env,
                                             isRunningUnitTests: false, allowOverrides: false)
        XCTAssertTrue(release.path.hasSuffix("/Application Support/Greenwick"), release.path)
        // A release build with another bundle ID ignores it as well
        let other = AppPaths.dataDirectory(bundleID: "com.greenwick.app.ci", environment: env,
                                           isRunningUnitTests: false, allowOverrides: false)
        XCTAssertTrue(other.path.hasSuffix("/Application Support/Greenwick-com.greenwick.app.ci"), other.path)
        // Debug builds (tests, screenshots) may use it
        let debug = AppPaths.dataDirectory(bundleID: "com.greenwick.app.ci", environment: env,
                                           isRunningUnitTests: false, allowOverrides: true)
        XCTAssertEqual(debug.path, "/tmp/copied-journal")
    }

    func testReleaseBuildsIgnoreTheKeychainServiceOverride() {
        let env = ["GREENWICK_KEYCHAIN_SERVICE": "somewhere-else"]
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app.ci", environment: env,
                                                isRunningUnitTests: false, allowOverrides: false),
                       "com.greenwick.app.ci")
        XCTAssertEqual(AppPaths.keychainService(bundleID: "com.greenwick.app.ci", environment: env,
                                                isRunningUnitTests: false, allowOverrides: true),
                       "somewhere-else")
    }

    func testThisTestBuildIsADebugBuild() {
        XCTAssertTrue(AppPaths.allowsEnvironmentOverrides, "Unit tests run the Debug configuration")
    }

    /// Xcode adds `com.apple.security.get-task-allow` (lets other processes attach a
    /// debugger) unless base entitlements injection is off for Release.
    func testReleaseConfigurationDoesNotInjectGetTaskAllow() throws {
        let projectFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let spec = try String(contentsOf: projectFile, encoding: .utf8)
        let release = try XCTUnwrap(spec.range(of: "configs:\n        Release:"), "Release settings block")
        let block = spec[release.upperBound...].prefix(400)
        XCTAssertTrue(block.contains("CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO"), String(block))
        let entitlements = try String(contentsOf: projectFile.deletingLastPathComponent()
            .appendingPathComponent("StockJournal/Greenwick.entitlements"), encoding: .utf8)
        XCTAssertFalse(entitlements.contains("get-task-allow"))
    }
}
