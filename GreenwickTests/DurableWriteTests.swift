import Foundation
import XCTest
@testable import Greenwick

/// Final review #6 (and Dojix #6): `SecureFileWriter` puts a save on stable storage before it
/// returns: `F_FULLFSYNC` of the contents before the rename, a flush of the folder after it.
/// Callers rely on that (the Keychain records the new journal generation, a key rotation
/// deletes the old key) only after `write` returned.
final class DurableWriteTests: XCTestCase {
    /// The contents are flushed before the rename and the folder after it, so a power loss
    /// can't leave the old file in place once the Keychain records the new generation (or a
    /// rotation deletes the old key)
    func testSaveFlushesTheFileBeforeTheRenameAndTheFolderAfter() throws {
        let folder = try makeScratchFolder()
        let destination = folder.appendingPathComponent("file.bin")
        try Data("old".utf8).write(to: destination)
        let new = Data("new contents".utf8)
        let events = EventLog()
        let sync = SecureFileWriter.Sync(
            file: { fd in
                events.add((try? Data(contentsOf: destination)) == new ? "file:after-rename" : "file:before-rename")
                return fcntl(fd, F_FULLFSYNC) == 0 ? 0 : fsync(fd)
            },
            directory: { fd in
                events.add((try? Data(contentsOf: destination)) == new ? "folder:after-rename" : "folder:before-rename")
                return fsync(fd)
            })

        try SecureFileWriter.write(new, to: destination, sync: sync)
        XCTAssertEqual(events.entries, ["file:before-rename", "folder:after-rename"])
        XCTAssertEqual(try Data(contentsOf: destination), new)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["file.bin"])
    }

    /// A failing flush of the contents is a failed save (the old file stays)
    func testFailedFlushKeepsTheOldFile() throws {
        let folder = try makeScratchFolder()
        let destination = folder.appendingPathComponent("file.bin")
        try Data("old".utf8).write(to: destination)
        let failing = SecureFileWriter.Sync(file: { _ in errno = EIO; return -1 }, directory: { _ in 0 })
        XCTAssertThrowsError(try SecureFileWriter.write(Data("new".utf8), to: destination, sync: failing))
        XCTAssertEqual(try Data(contentsOf: destination), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["file.bin"])
    }
}

/// Thread-safe list of strings (sync callbacks are `@Sendable`)
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var entries: [String] { lock.withLock { items } }
}
