import CommonCrypto
import Foundation
import Security

/// Shared PBKDF2-SHA256 key derivation and salt generation.
///
/// Used by `AppLockVault` (lock password), `PasswordHasher` (older lock installs) and
/// `BackupEncryption` (password-protected backups).
enum KeyDerivation {
    /// Iteration count of `PasswordHasher` (older App Lock installs) when none is given.
    /// New password keys use 600,000 (`AppLockVault.defaultIterations`).
    static let defaultIterations: UInt32 = 100_000

    /// Standard salt length in bytes
    static let defaultSaltLength = 16

    /// Standard derived key length in bytes (256-bit)
    static let defaultKeyLength = 32

    /// Derive a key from password + salt using PBKDF2-SHA256
    /// Returns nil if the password is empty or not valid UTF-8
    static func deriveKey(
        password: String,
        salt: Data,
        iterations: UInt32 = defaultIterations,
        keyLength: Int = defaultKeyLength
    ) -> Data? {
        guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
            return nil
        }

        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else { return nil }
        return derivedKey
    }

    /// Generate a cryptographically random salt
    static func generateSalt(length: Int = defaultSaltLength) -> Data {
        var salt = Data(count: length)
        salt.withUnsafeMutableBytes { buffer in
            // Safe: Data(count:) always allocates a contiguous buffer with non-nil baseAddress
            _ = SecRandomCopyBytes(kSecRandomDefault, length, buffer.baseAddress!)
        }
        return salt
    }
}
