import Darwin
import Foundation
import os

/// Writes a file atomically and owner-only, without any path-based step an attacker could race.
///
/// The temporary file gets a random name in the destination folder and is created with
/// `open(O_CREAT | O_EXCL | O_NOFOLLOW)` at mode 0600, so it can't be a planted file or
/// symlink. All writing, `fchmod` and the flush to disk go through that descriptor, and
/// `rename(2)` then replaces the destination name itself (a symlink there is replaced, never
/// followed). Nothing is reopened or chmod'ed by path afterwards.
///
/// Durability (power loss, kernel panic): on macOS `fsync` only hands the data to the drive,
/// which may still lose it. The contents are flushed with `F_FULLFSYNC` before the rename,
/// and the folder is flushed after it, so once `write` returns the new file is on stable
/// storage. Callers rely on this: the journal records its save generation in the Keychain,
/// and a key rotation deletes the old key, only after `write` returned.
enum SecureFileWriter {
    /// Owner read/write only
    static let ownerOnly: mode_t = 0o600

    /// How the written data is forced onto stable storage (tests record the calls)
    struct Sync: Sendable {
        /// Flush the temporary file's contents (before the rename). Returns 0 on success.
        let file: @Sendable (Int32) -> Int32
        /// Flush the folder, so the rename itself survives a power loss (after the rename)
        let directory: @Sendable (Int32) -> Int32

        /// `F_FULLFSYNC` (falls back to `fsync` where the file system doesn't support it)
        static let full = Sync(file: fullSync, directory: fullSync)

        private static func fullSync(_ fd: Int32) -> Int32 {
            fcntl(fd, F_FULLFSYNC) == 0 ? 0 : fsync(fd)
        }
    }

    private static let logger = Logger(subsystem: "com.greenwick", category: "SecureFileWriter")

    static func write(_ data: Data, to url: URL, sync: Sync = .full) throws {
        let destination = url.path
        // Starts with the destination's name, so "erase all local data" finds a leftover
        // from a crash (`DatabaseEncryption.journalFiles`)
        let temporary = destination + ".saving-" + UUID().uuidString
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, ownerOnly)
        guard fd >= 0 else { throw posixError() }
        var isRenamed = false
        defer {
            close(fd)
            if !isRenamed { unlink(temporary) }
        }
        // The umask can only narrow the mode; make it exactly 0600 on the open descriptor
        guard fchmod(fd, ownerOnly) == 0 else { throw posixError() }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return } // empty data: nothing to write
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                offset += written
            }
        }
        guard sync.file(fd) == 0 else { throw posixError() }
        guard rename(temporary, destination) == 0 else { throw posixError() }
        isRenamed = true
        syncDirectory(of: url, sync: sync)
    }

    /// Flush the folder entry of the rename. The new file is already in place and complete,
    /// so a failure here is logged, not thrown (some file systems can't flush a folder).
    private static func syncDirectory(of url: URL, sync: Sync) {
        let folder = url.deletingLastPathComponent().path
        let dirFD = open(folder, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard dirFD >= 0 else {
            logger.warning("Could not open the folder to flush it (errno \(errno))")
            return
        }
        defer { close(dirFD) }
        if sync.directory(dirFD) != 0 {
            logger.warning("Could not flush the folder after saving (errno \(errno))")
        }
    }

    private static func posixError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
