import CryptoKit
import Foundation
import GRDB
import XCTest
@testable import Greenwick

/// Keychain stand-in: the vault's logic runs exactly as in the app, without touching the
/// real Keychain (and without any system prompt).
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var unreadable: Set<String> = []

    func lookup(_ account: String) -> SecretLookup {
        lock.withLock {
            if unreadable.contains(account) { return .failed(-25308) } // errSecInteractionNotAllowed
            return items[account].map(SecretLookup.found) ?? .absent
        }
    }

    /// Reads of `accounts` fail the way a locked keychain or a refused access prompt does
    /// (the item may still exist)
    func failReads(of accounts: Set<String>) { lock.withLock { unreadable = accounts } }

    @discardableResult
    func write(_ data: Data, account: String) -> Bool {
        lock.withLock { items[account] = data }
        return true
    }

    func delete(_ account: String) { lock.withLock { _ = items.removeValue(forKey: account) } }

    var accounts: Set<String> { lock.withLock { Set(items.keys) } }
}

/// `.userPresence` stand-in. `isSupported == false` behaves like an ad-hoc signed build
/// (the data protection Keychain refuses the item). `ownerConfirms` is the answer to the
/// Touch ID / Mac password prompt.
final class MemoryPresenceStore: PresenceProtectedStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: Data?
    let isSupported: Bool
    var ownerConfirms = true
    private(set) var prompts = 0

    init(isSupported: Bool = true) { self.isSupported = isSupported }

    func store(_ secret: Data) -> Bool {
        guard isSupported else { return false }
        lock.withLock { self.secret = secret }
        return true
    }

    func hasSecret() -> Bool { lock.withLock { secret != nil } }

    func retrieve(reason: String) async -> Data? {
        lock.withLock {
            prompts += 1
            return ownerConfirms ? secret : nil
        }
    }

    func delete() { lock.withLock { secret = nil } }
}

/// Touch ID / Mac password confirmation stand-in (never shows a system prompt)
final class MemoryOwnerCheck: DeviceOwnerCheck, @unchecked Sendable {
    private let lock = NSLock()
    private let confirms: Bool
    private var count = 0

    init(confirms: Bool = true) { self.confirms = confirms }

    var prompts: Int { lock.withLock { count } }

    func confirm(reason: String) async -> Bool {
        lock.withLock { count += 1 }
        return confirms
    }
}

/// A clock tests move forward by hand
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// A disk that can be made "full": journal writes then fail with ENOSPC (renames, reads and
/// everything else still work, as on a real full disk)
final class FlakyDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var full = false
    private(set) var failedWrites = 0

    var isFull: Bool {
        get { lock.withLock { full } }
        set { lock.withLock { full = newValue } }
    }

    var writer: JournalFileWriter {
        JournalFileWriter { [self] data, url in
            let refuse = lock.withLock { () -> Bool in
                if full { failedWrites += 1 }
                return full
            }
            if refuse { throw POSIXError(.ENOSPC) }
            try SecureFileWriter.write(data, to: url)
        }
    }
}

extension XCTestCase {
    /// A fresh folder for one test's journal, removed afterwards
    func makeScratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gw-sec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A vault with in-memory stores and a low PBKDF2 count (fast tests; the real count is
    /// checked separately)
    func makeVault(presenceSupported: Bool = true,
                   owner: MemoryOwnerCheck = MemoryOwnerCheck()) -> (AppLockVault, MemorySecretStore, MemoryPresenceStore) {
        let store = MemorySecretStore()
        let presence = MemoryPresenceStore(isSupported: presenceSupported)
        var vault = AppLockVault(store: store, presence: presence)
        vault.owner = owner
        vault.ledger = JournalLedger(store: MemorySecretStore())
        vault.iterations = 1_000
        vault.throttle = UnlockThrottle(store: MemorySecretStore())
        return (vault, store, presence)
    }

    /// The data folder holds the sealed journal and the (empty) single-copy lock file, nothing else
    func assertOnlyTheJournal(in folder: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       ["Greenwick.sqlite", InstanceLock.fileName], file: file, line: line)
        let lockFile = folder.appendingPathComponent(InstanceLock.fileName)
        XCTAssertEqual(try Data(contentsOf: lockFile), Data(), "The lock file holds no data", file: file, line: line)
    }

    /// The 30 fictional sample trades
    func sampleTrades() -> [Trade] { DemoDataGenerator.generateTrades() }

    /// SQLite file bytes of a journal holding `trades`, optionally altered with raw SQL
    /// (to build hostile backups the app itself would never write)
    func backupBytes(with trades: [Trade], sql: [String] = []) throws -> Data {
        let db = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: db).bulkInsert(trades)
        try db.dbQueue.writeWithoutTransaction { db in
            for statement in sql { try db.execute(sql: statement) }
        }
        return try db.serializedSnapshot()
    }
}
