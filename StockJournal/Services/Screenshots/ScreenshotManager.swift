import AppKit
import CryptoKit
import Foundation
import os

/// The image files attached to trades, under `<data folder>/Screenshots/<trade id>/<UUID>.jpg`.
///
/// Every screenshot is sealed with the journal's key (`ScreenshotFormat`, AES-256-GCM) and
/// written with `SecureFileWriter` (owner-only, atomic, never through a link). The image is
/// encoded and encrypted in memory; no plaintext copy is written anywhere. Reading decrypts
/// into memory only.
///
/// The key is the open journal's and is set by `AppState` (`useKey`): while Greenwick is
/// locked there is none, so nothing is decrypted, shown or written. Key rotation re-seals
/// every file (`reseal`); plain files from older versions are sealed by `sealLegacyFiles`
/// (`ScreenshotManager+Keys.swift`). Only names the app itself creates (`<UUID>.jpg`) are
/// ever read, written or deleted.
final class ScreenshotManager: @unchecked Sendable {
    /// Folder holding every trade's screenshot folder
    let baseDir: URL
    /// Writes a sealed file (tests inject failures)
    let writer: JournalFileWriter
    /// Test seam: runs while a new screenshot is saved (file lock held, key taken), before
    /// it is written
    let willSaveImage: (@Sendable () -> Void)?
    static let logger = Logger(subsystem: "com.greenwick", category: "ScreenshotManager")

    /// Held while a file is read or written with a key and while the key changes, so a
    /// re-seal for a key rotation and a save with the key of the moment can't interleave
    /// (a file sealed with a key taken before the rotation and written after the re-seal
    /// passed it would need the dropped old key). All access to `activeKey` goes through it.
    let fileLock = NSLock()
    /// The journal's key while unlocked; nil while locked. Guarded by `fileLock`.
    var activeKey: SymmetricKey?

    init(baseDir: URL, writer: JournalFileWriter = .secure, willSaveImage: (@Sendable () -> Void)? = nil) {
        self.baseDir = baseDir
        self.writer = writer
        self.willSaveImage = willSaveImage
    }

    // MARK: - Key

    /// Use `key` from now on (the journal's key), or nil while locked. Waits for a file
    /// being written to finish, so nothing is written with a key after it was taken away.
    func useKey(_ key: SymmetricKey?) {
        fileLock.withLock { activeKey = key }
    }

    /// A key is set (the journal is open and unlocked)
    var hasKey: Bool { fileLock.withLock { activeKey != nil } }

    // MARK: - Paths

    /// Get the screenshots directory for a trade
    func screenshotDir(for tradeId: Int64) -> URL {
        baseDir.appendingPathComponent("\(tradeId)", isDirectory: true)
    }

    /// Whether `filename` is one the app itself writes: `<UUID>.jpg`. Everything else
    /// (".", "..", dot-files, paths, other extensions) comes from a crafted database.
    static func isValidFilename(_ filename: String) -> Bool {
        guard filename.count == 40, filename.lowercased().hasSuffix(".jpg") else { return false }
        return UUID(uuidString: String(filename.dropLast(4))) != nil
    }

    /// Full URL for a screenshot, or nil if the name isn't one the app writes or would
    /// resolve outside the trade's screenshot folder
    func imageURL(filename: String, for tradeId: Int64) -> URL? {
        guard Self.isValidFilename(filename) else {
            Self.logger.error("Rejected unsafe screenshot filename")
            return nil
        }
        let dir = screenshotDir(for: tradeId).standardizedFileURL
        let url = dir.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        guard url.deletingLastPathComponent().path == dir.path else { return nil }
        return url
    }

    // MARK: - Saving and loading

    /// Encode `image` as JPEG (in memory) and save it sealed. Returns the new filename.
    func saveImage(_ image: NSImage, for tradeId: Int64) throws -> String {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw ScreenshotError.encodingFailed
        }
        return try saveImageData(jpeg, for: tradeId)
    }

    /// Seal `imageData` with the journal's key and write it into the trade's folder.
    /// Throws `locked` while Greenwick is locked (nothing is written). Returns the filename.
    func saveImageData(_ imageData: Data, for tradeId: Int64) throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        guard let url = imageURL(filename: filename, for: tradeId) else { throw ScreenshotError.invalidFilename }
        try fileLock.withLock {
            // The key of this moment (a rotation may have just switched it)
            guard let key = activeKey else { throw ScreenshotError.locked }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            willSaveImage?()
            try writeSealed(imageData, key: key, to: url)
        }
        Self.logger.debug("Saved an encrypted screenshot for trade \(tradeId)")
        return filename
    }

    /// Load an image by filename for a trade (nil if missing, invalid or locked)
    func loadImage(filename: String, for tradeId: Int64) -> NSImage? {
        loadImageData(filename: filename, for: tradeId).flatMap(NSImage.init(data:))
    }

    /// The decrypted image bytes, in memory only. nil while locked (nothing is read), for a
    /// name the app doesn't write, or a file that doesn't open with the journal's key. A
    /// plain file from an older version (not sealed yet) is returned as it is.
    func loadImageData(filename: String, for tradeId: Int64) -> Data? {
        guard let url = imageURL(filename: filename, for: tradeId) else { return nil }
        return fileLock.withLock {
            guard let key = activeKey, let file = try? Data(contentsOf: url) else { return nil }
            guard ScreenshotFormat.isSealed(file) else { return file }
            return try? ScreenshotFormat.open(file, key: key, name: filename)
        }
    }

    /// Delete a screenshot file (only a regular file inside the trade's own folder)
    func deleteImage(filename: String, for tradeId: Int64) throws {
        guard let url = imageURL(filename: filename, for: tradeId) else {
            throw ScreenshotError.invalidFilename
        }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if FileManager.default.fileExists(atPath: url.path),
           values?.isRegularFile != true || values?.isSymbolicLink == true {
            throw ScreenshotError.invalidFilename
        }
        try fileLock.withLock { try FileManager.default.removeItem(at: url) }
        Self.logger.debug("Deleted screenshot for trade \(tradeId)")
    }

    /// Delete every screenshot (sealed or not) and the folder ("Erase All Local Data").
    /// Returns whether the folder is gone.
    @discardableResult
    func removeAll() -> Bool {
        fileLock.withLock {
            let files = FileManager.default
            if files.fileExists(atPath: baseDir.path) {
                do {
                    try files.removeItem(at: baseDir)
                } catch {
                    Self.logger.error("Could not delete the screenshots: \(error.localizedDescription)")
                }
            }
            return (try? files.attributesOfItem(atPath: baseDir.path)) == nil
        }
    }

    /// Seal `image` for `url`'s name with `key`, write it, and read it back: it must open
    /// with `key` to the same bytes. Call with `fileLock` held.
    func writeSealed(_ image: Data, key: SymmetricKey, to url: URL) throws {
        let name = url.lastPathComponent
        try writer.write(try ScreenshotFormat.seal(image, key: key, name: name), url)
        let written = try Data(contentsOf: url)
        guard (try? ScreenshotFormat.open(written, key: key, name: name)) == image else {
            throw ScreenshotError.notVerified
        }
    }

    enum ScreenshotError: LocalizedError {
        case encodingFailed
        case invalidFilename
        case locked
        case notVerified
        var errorDescription: String? {
            switch self {
            case .encodingFailed: "Failed to encode image as JPEG"
            case .invalidFilename: "That screenshot name isn't valid, so it was left alone."
            case .locked: "Greenwick is locked."
            case .notVerified: "The encrypted screenshot didn't read back correctly."
            }
        }
    }
}
