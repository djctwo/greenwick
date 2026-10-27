import Darwin
import Foundation
import os

/// One Greenwick per data folder.
///
/// The journal lives in memory and every save rewrites the whole file, so two running
/// copies (the same app at two paths, `open -n`, a second build) would silently overwrite
/// each other's changes. The first copy holds an exclusive `flock` on `Greenwick.lock` in the
/// data folder for as long as it runs; a second copy can't take it and opens nothing.
/// The system releases the lock when the process ends, even after a crash.
final class InstanceLock: @unchecked Sendable {
    enum Outcome {
        /// This process holds the lock (keep the object alive)
        case acquired(InstanceLock)
        /// Another running copy holds it
        case heldElsewhere
        /// The lock file couldn't be opened or locked for another reason (logged); the app
        /// carries on as before this guard existed rather than refusing to start
        case unavailable
    }

    static let fileName = "Greenwick.lock"
    private static let logger = Logger(subsystem: "com.greenwick", category: "InstanceLock")

    private let lock = NSLock()
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    /// Take the lock for the data folder `directory` (created if missing)
    static func acquire(in directory: URL) -> Outcome {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(fileName).path
        // Owner-only, never through a planted symlink; holds no data
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            logger.error("Could not open the instance lock file (errno \(errno))")
            return .unavailable
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(fd)
            if error == EWOULDBLOCK { return .heldElsewhere }
            logger.error("Could not take the instance lock (errno \(error))")
            return .unavailable
        }
        return .acquired(InstanceLock(fd: fd))
    }

    /// Let another copy open the journal (after the final save)
    func release() {
        lock.withLock {
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
    }

    deinit { release() }
}
