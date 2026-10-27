import CryptoKit
import Foundation
import os

/// Password protection for backup files.
///
/// Current format (version 2), written for every new protected backup:
///
///     "GWBK" | version (1 byte, 2) | PBKDF2 rounds (UInt32, big-endian) | salt length (1 byte, 16) | salt
///     | AES-256-GCM sealed box (nonce | ciphertext | tag)
///
/// The key comes from the password with PBKDF2-SHA256 (600,000 rounds, random 16-byte salt
/// per file). The whole header is the AES-GCM associated data, so changing any of it (round
/// count, salt, version) makes the file fail to open. Round counts above
/// `maximumIterations` are refused before any key derivation, so a crafted file can't make
/// a restore hang.
///
/// Older Greenwick versions could write "SJNL" | salt | sealed box with 100,000 rounds and no
/// associated data. Those files still restore (read-only support); nothing writes them.
enum BackupEncryption {
    private static let logger = Logger(subsystem: "com.greenwick", category: "BackupEncryption")

    static let magic = Data("GWBK".utf8)
    static let version: UInt8 = 2
    /// PBKDF2-SHA256 rounds for new backups (same as the App Lock password)
    static let iterations: UInt32 = AppLockVault.defaultIterations
    /// Highest round count a backup may ask for when it is read
    static let maximumIterations: UInt32 = 10_000_000
    static let saltLength = 16
    /// magic + version + rounds + salt length + salt
    static let headerLength = 4 + 1 + 4 + 1 + 16

    static let legacyMagic = Data("SJNL".utf8)
    static let legacyIterations: UInt32 = 100_000

    /// Nonce (12) + tag (16)
    private static let sealOverhead = 28

    enum Format: Equatable {
        /// Not password-protected (a plain SQLite backup, or not a backup at all)
        case plain
        case protected
        /// Written by an older version ("SJNL", 100,000 rounds)
        case legacyProtected
    }

    static func format(of data: Data) -> Format {
        if data.count >= 4, data.prefix(4) == magic { return .protected }
        if data.count >= 4, data.prefix(4) == legacyMagic { return .legacyProtected }
        return .plain
    }

    static func isProtected(_ data: Data) -> Bool { format(of: data) != .plain }

    // MARK: - Encrypt (always the current format)

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        try AppLockVault.checkStrength(password)
        let salt = KeyDerivation.generateSalt(length: saltLength)
        var header = magic
        header.append(version)
        header.append(contentsOf: withUnsafeBytes(of: iterations.bigEndian) { Array($0) })
        header.append(UInt8(saltLength))
        header.append(salt)
        let key = try derive(password, salt: salt, iterations: iterations)
        guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header).combined else {
            throw Failure.encryptionFailed
        }
        logger.debug("Backup sealed")
        return header + sealed
    }

    // MARK: - Decrypt

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw Failure.passwordRequired }
        switch format(of: data) {
        case .plain: throw Failure.notProtected
        case .legacyProtected: return try decryptLegacy(data, password: password)
        case .protected: break
        }
        let bytes = [UInt8](data)
        guard bytes.count >= headerLength + sealOverhead else { throw Failure.damaged }
        guard bytes[4] == version else { throw Failure.unsupportedVersion }
        let rounds = bytes[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (1...maximumIterations).contains(rounds) else { throw Failure.damaged }
        guard Int(bytes[9]) == saltLength else { throw Failure.damaged }
        let header = Data(bytes[0..<headerLength])
        let salt = Data(bytes[10..<headerLength])
        let key = try derive(password, salt: salt, iterations: rounds)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw Failure.wrongPassword
        }
    }

    /// "SJNL" | salt (16) | sealed box, 100,000 rounds (read-only support for older files)
    private static func decryptLegacy(_ data: Data, password: String) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 + 16 + sealOverhead else { throw Failure.damaged }
        let key = try derive(password, salt: Data(bytes[4..<20]), iterations: legacyIterations)
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: Data(bytes[20...])), using: key)
        } catch {
            throw Failure.wrongPassword
        }
    }

    private static func derive(_ password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard let raw = KeyDerivation.deriveKey(password: password, salt: salt, iterations: iterations) else {
            throw Failure.wrongPassword
        }
        return SymmetricKey(data: raw)
    }

    // MARK: - Errors

    enum Failure: LocalizedError, Equatable {
        case passwordRequired
        case wrongPassword
        case damaged
        case unsupportedVersion
        case notProtected
        case encryptionFailed

        var errorDescription: String? {
            switch self {
            case .passwordRequired:
                "This backup is protected with a password. Enter it to restore."
            case .wrongPassword:
                "Wrong password for this backup (or the file was changed). Your journal was not changed."
            case .damaged:
                "This backup file is damaged or not a Greenwick backup. Your journal was not changed."
            case .unsupportedVersion:
                "This backup was made by a newer version of Greenwick. Your journal was not changed."
            case .notProtected:
                "This backup is not password-protected."
            case .encryptionFailed:
                "The backup could not be encrypted."
            }
        }
    }
}
