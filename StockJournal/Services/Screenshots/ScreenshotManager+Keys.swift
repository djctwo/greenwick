import CryptoKit
import Foundation

/// Moving screenshots to a new key (key rotation) and sealing plain files left by older versions.
///
/// Both work file by file under `fileLock`, with the key of that moment, and replace each
/// file atomically (`SecureFileWriter`): a crash leaves every file either as it was or fully
/// re-written, so running again later simply continues (files already done are skipped).
extension ScreenshotManager {
    /// What the screenshots folder holds
    struct Listing {
        /// Every regular file with an app-created name, in every trade's folder
        var files: [URL] = []
        /// Folders that exist but could not be listed (their files are unknown)
        var unlisted: [URL] = []
        /// Temporary files a crash left behind mid-write (they only ever hold sealed bytes)
        var leftovers: [URL] = []
    }

    // MARK: - Key rotation

    /// Key rotation: from now on new screenshots use `new` (when a key is set), and every
    /// file that opens with one of `olds` is re-sealed with `new` and read back. Plain files
    /// from older versions are sealed with `new` too. Returns what may still need an old key:
    /// files that couldn't be read, or opened with an old key but couldn't be re-written, and
    /// folders that couldn't be listed. The caller keeps the old keys while it isn't empty.
    ///
    /// The key switches and the files are listed under the file lock in one step: a save that
    /// took the old key finished before (and is in the list), any later save gets `new`.
    /// A file that opens with none of the keys (damaged) is left alone: no key could help it.
    @discardableResult
    func reseal(from olds: [SymmetricKey], to new: SymmetricKey) -> [URL] {
        let listing: Listing = fileLock.withLock {
            if activeKey != nil { activeKey = new }
            return list()
        }
        var pending = listing.unlisted
        for file in listing.files {
            let needsOld = fileLock.withLock { resealOne(file, from: olds, to: new) }
            if needsOld { pending.append(file) }
        }
        if !pending.isEmpty {
            Self.logger.error("\(pending.count) screenshot file(s) or folder(s) couldn't be re-sealed yet")
        }
        return pending
    }

    /// Re-seal one file (file lock held). Returns true when it may still need an old key.
    private func resealOne(_ file: URL, from olds: [SymmetricKey], to new: SymmetricKey) -> Bool {
        let name = file.lastPathComponent
        guard let data = try? Data(contentsOf: file) else {
            // Deleted meanwhile needs no key; a file that exists but can't be read might
            return (try? FileManager.default.attributesOfItem(atPath: file.path)) != nil
        }
        let image: Data
        let neededOld: Bool
        if ScreenshotFormat.isSealed(data) {
            if (try? ScreenshotFormat.open(data, key: new, name: name)) != nil { return false }
            guard let opened = olds.lazy.compactMap({ try? ScreenshotFormat.open(data, key: $0, name: name) }).first
            else {
                Self.logger.error("A screenshot opens with none of the journal's keys; left as it is")
                return false
            }
            image = opened
            neededOld = true
        } else {
            image = data // a plain file from an older version: needs no key to read
            neededOld = false
        }
        do {
            try writeSealed(image, key: new, to: file)
            return false
        } catch {
            Self.logger.error("Could not re-seal a screenshot: \(error.localizedDescription)")
            return neededOld
        }
    }

    // MARK: - Files from older versions

    /// Seal the plain image files older versions saved, in place, with the journal's key;
    /// remove temporary files a crash left behind. Does nothing while locked, and stops as
    /// soon as Greenwick locks. Files that are already sealed are skipped. Returns how many
    /// files were sealed.
    @discardableResult
    func sealLegacyFiles() -> Int {
        let listing: Listing? = fileLock.withLock {
            guard activeKey != nil else { return nil }
            let found = list()
            // Every write runs under this lock, so none is in progress: these are crash leftovers
            for leftover in found.leftovers { try? FileManager.default.removeItem(at: leftover) }
            return found
        }
        guard let listing else { return 0 }
        var count = 0
        for file in listing.files {
            let sealed = fileLock.withLock { sealIfPlain(file) }
            if sealed { count += 1 }
        }
        if count > 0 { Self.logger.notice("Encrypted \(count) screenshot(s) saved by an older version") }
        return count
    }

    /// Seal one plain file with the key of this moment (file lock held). Returns whether it did.
    private func sealIfPlain(_ file: URL) -> Bool {
        // Locked meanwhile: write nothing
        guard let key = activeKey,
              let data = try? Data(contentsOf: file), !ScreenshotFormat.isSealed(data) else { return false }
        do {
            try writeSealed(data, key: key, to: file)
            return true
        } catch {
            Self.logger.error("Could not encrypt a screenshot from an older version: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Listing

    /// Every app-named regular file (no links) in every trade's folder, the folders that
    /// couldn't be listed, and crash leftovers. Call with `fileLock` held.
    func list() -> Listing {
        let fileManager = FileManager.default
        var listing = Listing()
        guard Self.type(of: baseDir) == .typeDirectory else { return listing }
        guard let folders = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            Self.logger.error("Could not list the screenshots folder")
            listing.unlisted.append(baseDir)
            return listing
        }
        for folder in folders where Self.type(of: folder) == .typeDirectory {
            guard let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                Self.logger.error("Could not list a trade's screenshot folder")
                listing.unlisted.append(folder)
                continue
            }
            for entry in entries where Self.type(of: entry) == .typeRegular {
                let name = entry.lastPathComponent
                if Self.isValidFilename(name) {
                    listing.files.append(entry)
                } else if let range = name.range(of: ".saving-"),
                          Self.isValidFilename(String(name[..<range.lowerBound])) {
                    listing.leftovers.append(entry)
                }
            }
        }
        return listing
    }

    /// The item's own type, read without following a symbolic link (nil if it doesn't exist)
    private static func type(of url: URL) -> FileAttributeType? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType
    }
}
