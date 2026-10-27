import AppKit
import CryptoKit
import XCTest
@testable import Greenwick

/// Trade screenshots on disk: sealed with the journal's key, decrypted into memory only,
/// nothing read or written without a key, plain files from older versions sealed in place
/// (also after an interrupted run), and a save racing a key rotation's re-seal.
final class ScreenshotStorageTests: XCTestCase {
    /// Starts like a JPEG, with a marker that must never appear on disk in the clear
    static let marker = Data("fictional chart pixels: entry 101.25 exit 103.80".utf8)
    static let jpegLike = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data("JFIF".utf8) + marker

    // MARK: - Sealed on disk, read back in memory

    func testNewScreenshotIsSealedOnDisk() throws {
        let key = SymmetricKey(size: .bits256)
        let manager = ScreenshotManager(baseDir: try makeScratchFolder())
        manager.useKey(key)

        let name = try manager.saveImageData(Self.jpegLike, for: 7)
        let url = try XCTUnwrap(manager.imageURL(filename: name, for: 7))
        let onDisk = try Data(contentsOf: url)
        Self.assertNotAnImage(onDisk)
        XCTAssertNil(onDisk.range(of: Self.marker), "Image bytes are in the file in the clear")
        XCTAssertTrue(onDisk.starts(with: ScreenshotFormat.header))
        XCTAssertEqual(try ScreenshotFormat.open(onDisk, key: key, name: name), Self.jpegLike)
        XCTAssertEqual(try Self.mode(of: url), 0o600)
        XCTAssertEqual(try Self.mode(of: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path),
                       [name], "No temporary or plaintext copy next to it")
    }

    /// The app's own path: an NSImage is encoded to JPEG in memory and only the sealed bytes
    /// are written; showing it decrypts into memory
    func testAttachedImageIsSealedAndDisplaysAfterDecrypting() throws {
        let manager = ScreenshotManager(baseDir: try makeScratchFolder())
        manager.useKey(SymmetricKey(size: .bits256))

        let name = try manager.saveImage(Self.sampleImage(), for: 3)
        let url = try XCTUnwrap(manager.imageURL(filename: name, for: 3))
        Self.assertNotAnImage(try Data(contentsOf: url))
        XCTAssertNil(NSImage(contentsOf: url), "The file on disk must not be a readable image")
        let shown = try XCTUnwrap(manager.loadImage(filename: name, for: 3))
        XCTAssertEqual(shown.size.width, 16, accuracy: 0.5)
        XCTAssertEqual(manager.loadImageData(filename: name, for: 3)?.prefix(2), Data([0xFF, 0xD8]))
    }

    func testAnotherKeyOrAnotherNameDoesNotOpen() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ScreenshotFormat.seal(Self.jpegLike, key: key, name: "a.jpg")
        XCTAssertThrowsError(try ScreenshotFormat.open(sealed, key: SymmetricKey(size: .bits256), name: "a.jpg"))
        XCTAssertThrowsError(try ScreenshotFormat.open(sealed, key: key, name: "b.jpg"))
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try ScreenshotFormat.open(tampered, key: key, name: "a.jpg"))
    }

    // MARK: - No key (locked): nothing decrypted, nothing written

    func testWithoutAKeyNothingIsDecryptedOrWritten() throws {
        let folder = try makeScratchFolder()
        let manager = ScreenshotManager(baseDir: folder)
        manager.useKey(SymmetricKey(size: .bits256))
        let name = try manager.saveImageData(Self.jpegLike, for: 1)
        let plain = try Self.plantPlainFile(in: folder, trade: 2)

        manager.useKey(nil) // what locking does
        XCTAssertNil(manager.loadImageData(filename: name, for: 1))
        XCTAssertNil(manager.loadImageData(filename: plain.lastPathComponent, for: 2),
                     "Not even an older version's plain file is shown while locked")
        XCTAssertThrowsError(try manager.saveImageData(Self.jpegLike, for: 1)) {
            XCTAssertEqual($0 as? ScreenshotManager.ScreenshotError, .locked)
        }
        XCTAssertEqual(manager.sealLegacyFiles(), 0)
        XCTAssertEqual(try Data(contentsOf: plain), Self.jpegLike, "Nothing is written while locked")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("1").path),
                       [name])
    }

    // MARK: - Plain files from older versions

    func testPlainScreenshotsFromAnOlderVersionAreSealedInPlace() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let manager = ScreenshotManager(baseDir: folder)
        manager.useKey(key)
        let sealedName = try manager.saveImageData(Self.jpegLike, for: 1)
        let sealedURL = folder.appendingPathComponent("1/\(sealedName)")
        let alreadySealed = try Data(contentsOf: sealedURL)
        let plain = [try Self.plantPlainFile(in: folder, trade: 1), try Self.plantPlainFile(in: folder, trade: 2)]

        XCTAssertEqual(manager.sealLegacyFiles(), 2)
        for file in plain {
            let onDisk = try Data(contentsOf: file)
            Self.assertNotAnImage(onDisk)
            XCTAssertEqual(try ScreenshotFormat.open(onDisk, key: key, name: file.lastPathComponent), Self.jpegLike)
            XCTAssertEqual(manager.loadImageData(filename: file.lastPathComponent,
                                                 for: Int64(file.deletingLastPathComponent().lastPathComponent) ?? 0),
                           Self.jpegLike)
        }
        XCTAssertEqual(try Data(contentsOf: sealedURL), alreadySealed, "An already sealed file is skipped")
        XCTAssertEqual(manager.sealLegacyFiles(), 0, "Running again changes nothing")
    }

    /// Greenwick stops in the middle (here: the second write fails, and a crash left a
    /// temporary file): sealed files stay sealed, the others stay intact, and the next run
    /// finishes without touching what is done
    func testAnInterruptedMigrationIsSafeAndResumes() throws {
        let folder = try makeScratchFolder()
        let key = SymmetricKey(size: .bits256)
        let first = try Self.plantPlainFile(in: folder, trade: 1)
        let second = try Self.plantPlainFile(in: folder, trade: 1)
        let leftover = folder.appendingPathComponent("1/\(first.lastPathComponent).saving-\(UUID().uuidString)")
        try Data("half-written sealed bytes".utf8).write(to: leftover)

        let writes = Counter()
        let crashing = JournalFileWriter { data, url in
            guard writes.next() == 1 else { throw POSIXError(.EIO) }
            try SecureFileWriter.write(data, to: url)
        }
        let interrupted = ScreenshotManager(baseDir: folder, writer: crashing)
        interrupted.useKey(key)
        XCTAssertEqual(interrupted.sealLegacyFiles(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path), "Crash leftover removed")
        let done = try XCTUnwrap([first, second].first { ScreenshotFormat.isSealed((try? Data(contentsOf: $0)) ?? Data()) })
        let notYet = done == first ? second : first
        XCTAssertEqual(try Data(contentsOf: notYet), Self.jpegLike, "The unfinished file is untouched")
        let doneBytes = try Data(contentsOf: done)

        let resumed = ScreenshotManager(baseDir: folder)
        resumed.useKey(key)
        XCTAssertEqual(resumed.sealLegacyFiles(), 1)
        XCTAssertEqual(try Data(contentsOf: done), doneBytes, "Already sealed: skipped")
        XCTAssertEqual(resumed.loadImageData(filename: notYet.lastPathComponent, for: 1), Self.jpegLike)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("1").path)),
                       [first.lastPathComponent, second.lastPathComponent])
    }

    // MARK: - A save racing a rotation's re-seal

    /// A save that took the old key just before the re-seal started is written before the
    /// re-seal lists the files (shared file lock), so it is re-sealed too; later saves use
    /// the new key
    func testAScreenshotBeingSavedWhenTheResealStartsIsResealed() throws {
        let folder = try makeScratchFolder()
        let old = SymmetricKey(size: .bits256), new = SymmetricKey(size: .bits256)
        let inWrite = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let isFirstSave = Box(true)
        let manager = ScreenshotManager(baseDir: folder, willSaveImage: {
            guard isFirstSave.value else { return } // only the save that races the re-seal waits
            isFirstSave.value = false
            inWrite.signal()
            _ = release.wait(timeout: .now() + 10)
        })
        manager.useKey(old)
        let saved = Box<String?>(nil), pending = Box<[URL]>([])
        let saveDone = DispatchSemaphore(value: 0), resealDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            saved.value = try? manager.saveImageData(Self.jpegLike, for: 1)
            saveDone.signal()
        }
        XCTAssertEqual(inWrite.wait(timeout: .now() + 10), .success)
        DispatchQueue.global().async {
            pending.value = manager.reseal(from: [old], to: new)
            resealDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.2) // let the re-seal reach the file lock
        release.signal()
        XCTAssertEqual(saveDone.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(resealDone.wait(timeout: .now() + 10), .success)

        let file = folder.appendingPathComponent("1/\(try XCTUnwrap(saved.value))")
        XCTAssertEqual(pending.value, [])
        XCTAssertNotNil(try? ScreenshotFormat.open(Data(contentsOf: file), key: new, name: file.lastPathComponent),
                        "The screenshot would be lost when the old key is deleted")
        let later = try manager.saveImageData(Self.jpegLike, for: 1)
        XCTAssertNotNil(try? ScreenshotFormat.open(Data(contentsOf: folder.appendingPathComponent("1/\(later)")),
                                                   key: new, name: later))
    }
}

// MARK: - Helpers

extension ScreenshotStorageTests {
    /// What an older Greenwick wrote: a plain image file with an app-created name
    static func plantPlainFile(in folder: URL, trade: Int64) throws -> URL {
        let dir = folder.appendingPathComponent("\(trade)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        try jpegLike.write(to: url)
        return url
    }

    static func assertNotAnImage(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(data.starts(with: [0xFF, 0xD8, 0xFF]), "JPEG magic on disk", file: file, line: line)
        XCTAssertFalse(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "PNG magic on disk", file: file, line: line)
        XCTAssertFalse(data.starts(with: Array("II*".utf8)) || data.starts(with: Array("MM".utf8)),
                       "TIFF magic on disk", file: file, line: line)
    }

    static func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? Int ?? -1) & 0o777
    }

    /// A small fictional chart image
    static func sampleImage() throws -> NSImage {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<16 { rep.setColor(.systemGreen, atX: x, y: x) }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        return image
    }
}

/// Thread-safe value for tests that run work on other threads
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Counts calls from any thread (1, 2, 3, ...)
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}
