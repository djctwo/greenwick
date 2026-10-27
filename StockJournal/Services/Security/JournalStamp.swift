import CryptoKit
import Foundation

/// Which save of the journal a file holds.
///
/// - `epoch`: a random 16-byte ID of the journal's line of saves. It changes when the owner
///   chooses to open an older copy, so copies from the abandoned line can never pass as
///   newer afterwards.
/// - `generation`: goes up by one with every save; it never goes down.
/// - `savedAtMillis`: when that save happened (milliseconds since 1970; shown to the owner).
struct JournalStamp: Codable, Equatable, Sendable {
    let epoch: Data
    let generation: UInt64
    let savedAtMillis: Int64

    static let epochLength = 16

    init(epoch: Data, generation: UInt64, savedAt: Date) {
        self.epoch = epoch
        self.generation = generation
        self.savedAtMillis = Int64((savedAt.timeIntervalSince1970 * 1000).rounded())
    }

    var savedAt: Date { Date(timeIntervalSince1970: Double(savedAtMillis) / 1000) }

    static func newEpoch() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }
}

/// The sealed journal file, format 2:
///
///     "GWJN" | version (1 byte, 2) | epoch (16 bytes) | generation (UInt64, big-endian)
///     | saved at (Int64 ms since 1970, big-endian) | AES-256-GCM sealed box (nonce | ciphertext | tag)
///
/// The 37-byte header is the AES-GCM associated data, so the epoch and generation can't be
/// changed without the key. Files sealed before stamps existed are a bare sealed box; they
/// open with no stamp (generation 0).
enum JournalFormat {
    static let magic = Data("GWJN".utf8)
    static let version: UInt8 = 2
    static let headerLength = 4 + 1 + JournalStamp.epochLength + 8 + 8

    static func seal(_ plaintext: Data, key: SymmetricKey, stamp: JournalStamp) throws -> Data {
        guard stamp.epoch.count == JournalStamp.epochLength else {
            throw DatabaseEncryption.EncryptionError.encryptionFailed
        }
        var header = magic
        header.append(version)
        header.append(stamp.epoch)
        header.append(contentsOf: withUnsafeBytes(of: stamp.generation.bigEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: stamp.savedAtMillis.bigEndian) { Array($0) })
        guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header).combined else {
            throw DatabaseEncryption.EncryptionError.encryptionFailed
        }
        return header + sealed
    }

    /// Decrypt a journal file. `stamp` is nil for a file sealed before stamps existed.
    static func open(_ file: Data, key: SymmetricKey) throws -> (plaintext: Data, stamp: JournalStamp?) {
        let bytes = [UInt8](file)
        if bytes.count > headerLength, file.prefix(4) == magic, bytes[4] == version {
            let header = Data(bytes[0..<headerLength])
            let epochEnd = 5 + JournalStamp.epochLength
            let epoch = Data(bytes[5..<epochEnd])
            let generation = bytes[epochEnd..<(epochEnd + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let rawMillis = bytes[(epochEnd + 8)..<headerLength].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            if let box = try? AES.GCM.SealedBox(combined: Data(bytes[headerLength...])),
               let plaintext = try? AES.GCM.open(box, using: key, authenticating: header) {
                let savedAt = Date(timeIntervalSince1970: Double(Int64(bitPattern: rawMillis)) / 1000)
                return (plaintext, JournalStamp(epoch: epoch, generation: generation, savedAt: savedAt))
            }
            // Falls through: an older file whose random nonce happens to start like a header
        }
        return (try DatabaseEncryption.open(file, key: key), nil)
    }

    /// SHA-256 of the sealed file's bytes (tells two files with the same stamp apart)
    static func fingerprint(of sealedFile: Data) -> Data {
        Data(SHA256.hash(data: sealedFile))
    }
}

/// The last journal save this Mac made, kept in the Keychain (same service as the journal
/// key, its own account, accessible when unlocked, this device only): its stamp and the
/// fingerprint of the file written.
struct JournalLedger: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let stamp: JournalStamp
        /// `JournalFormat.fingerprint` of the sealed file
        let fileHash: Data
    }

    let store: any SecretStore
    static let account = "journal_generation"

    static var live: JournalLedger { JournalLedger(store: KeychainSecretStore()) }

    /// The last recorded save (nil: never recorded, e.g. before this version, or unreadable)
    func read() -> Entry? {
        guard let data = store.read(Self.account) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    /// Record a save. Returns false if the Keychain refused: the journal itself is already
    /// saved, so the app keeps working (`JournalPersistence` logs it); the next save tries again.
    @discardableResult
    func record(_ entry: Entry) -> Bool {
        guard let data = try? JSONEncoder().encode(entry) else { return false }
        return store.write(data, account: Self.account)
    }

    func remove() { store.delete(Self.account) }

    // MARK: - Checking a journal file

    /// How a journal file compares with the last save recorded here
    enum Verdict: Equatable {
        /// The recorded save, or a later save of the same line (the Keychain fell behind),
        /// or nothing is recorded
        case expected
        /// Same line of saves, but an earlier generation
        case older
        /// Another line of saves (an abandoned one, or a file from before stamps existed),
        /// or the same generation with different content
        case differentCopy
    }

    /// Compare a journal file (its stamp, nil = from before stamps, and its bytes) with `last`
    static func verdict(file stamp: JournalStamp?, fileHash: Data, last: Entry?) -> Verdict {
        guard let last else { return .expected }
        guard let stamp else { return .older }
        guard stamp.epoch == last.stamp.epoch else { return .differentCopy }
        if stamp.generation < last.stamp.generation { return .older }
        if stamp.generation == last.stamp.generation, fileHash != last.fileHash { return .differentCopy }
        return .expected
    }
}
