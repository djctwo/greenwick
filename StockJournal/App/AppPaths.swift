import Foundation

/// Where Greenwick keeps its data on disk and in the Keychain.
///
/// The release build (bundle ID `com.greenwick.app`) uses
/// `~/Library/Application Support/Greenwick/` and the Keychain service
/// `com.greenwick.app`. Any other bundle ID (for example a local test build such as
/// `com.greenwick.app.test`) gets its own folder and Keychain service, so a test or
/// development build can never open, change or delete the data of an installed copy.
///
/// Debug builds (tests, UI tests, screenshots) can be pointed elsewhere with the
/// `GREENWICK_DATA_DIR` and `GREENWICK_KEYCHAIN_SERVICE` environment variables. Release
/// builds ignore both, so nobody can launch the installed app against a copied journal or a
/// different Keychain service.
enum AppPaths {
    /// Environment overrides are honoured only in Debug builds
    static let allowsEnvironmentOverrides: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static let productionBundleID = "com.greenwick.app"

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? productionBundleID
    }

    static var isProductionBundle: Bool {
        bundleID == productionBundleID
    }

    /// Keychain service name for API keys, the app lock and the database key.
    ///
    /// A Debug build with a non-release bundle ID can be given its own service with the
    /// `GREENWICK_KEYCHAIN_SERVICE` environment variable, so each UI test starts with no app
    /// lock and no saved keys. Release builds ignore it.
    static var keychainService: String {
        keychainService(
            bundleID: bundleID,
            environment: ProcessInfo.processInfo.environment,
            isRunningUnitTests: isRunningUnitTests
        )
    }

    static func keychainService(
        bundleID: String,
        environment: [String: String],
        isRunningUnitTests: Bool,
        allowOverrides: Bool = allowsEnvironmentOverrides
    ) -> String {
        if allowOverrides, bundleID != productionBundleID,
           let override = environment["GREENWICK_KEYCHAIN_SERVICE"], !override.isEmpty {
            return override
        }
        return isRunningUnitTests ? "\(bundleID).unittests" : bundleID
    }

    /// True when a Debug build is hosting the unit-test bundle
    static var isRunningUnitTests: Bool {
        allowsEnvironmentOverrides && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Folder holding the database and screenshots. Created on demand.
    static var dataDirectory: URL {
        let dir = dataDirectory(
            bundleID: bundleID,
            environment: ProcessInfo.processInfo.environment,
            isRunningUnitTests: isRunningUnitTests
        )
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func dataDirectory(
        bundleID: String,
        environment: [String: String],
        isRunningUnitTests: Bool,
        allowOverrides: Bool = allowsEnvironmentOverrides
    ) -> URL {
        let fileManager = FileManager.default
        if allowOverrides, let override = environment["GREENWICK_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if isRunningUnitTests {
            // Unit tests host the app: never let them touch a real data folder
            return fileManager.temporaryDirectory.appendingPathComponent("greenwick-unit-tests", isDirectory: true)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = bundleID == productionBundleID ? "Greenwick" : "Greenwick-\(bundleID)"
        return appSupport.appendingPathComponent(folder, isDirectory: true)
    }

    static var databaseURL: URL {
        dataDirectory.appendingPathComponent(Configuration.databaseFilename)
    }

    static var screenshotsDirectory: URL {
        dataDirectory.appendingPathComponent("Screenshots", isDirectory: true)
    }
}
