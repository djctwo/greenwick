import CommonCrypto
import Foundation

/// PBKDF2-SHA256 password hashing for app lock.
///
/// Produces a salted hash: `base64(salt):base64(derivedKey)`.
/// Uses 100,000 iterations and 16-byte random salt via `KeyDerivation`.
/// Backwards-compatible: detects legacy unsalted SHA-256 hashes on verification
/// and upgrades them transparently.
enum PasswordHasher {

    // MARK: - Hash

    /// Hash a password with a fresh random salt
    static func hash(_ password: String) -> String {
        let salt = KeyDerivation.generateSalt()
        let derived = KeyDerivation.deriveKey(password: password, salt: salt) ?? Data()
        return "\(salt.base64EncodedString()):\(derived.base64EncodedString())"
    }

    // MARK: - Verify

    /// Verify a password against a stored hash (supports both PBKDF2 and legacy SHA-256)
    static func verify(_ password: String, against stored: String) -> Bool {
        if stored.contains(":") {
            // PBKDF2 format: base64(salt):base64(derivedKey)
            let parts = stored.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let salt = Data(base64Encoded: String(parts[0])),
                  let expected = Data(base64Encoded: String(parts[1])),
                  let derived = KeyDerivation.deriveKey(password: password, salt: salt) else {
                return false
            }
            return constantTimeEqual(derived, expected)
        } else {
            // Legacy SHA-256 hex format (no salt)
            let legacy = legacySHA256(password)
            return constantTimeEqual(
                Array(legacy.utf8),
                Array(stored.utf8)
            )
        }
    }

    /// Whether a stored hash is the legacy SHA-256 format (needs upgrade)
    static func needsUpgrade(_ stored: String) -> Bool {
        !stored.contains(":")
    }

    // MARK: - Private

    /// Legacy SHA-256 hex hash (for backwards compatibility only)
    private static func legacySHA256(_ password: String) -> String {
        let data = Array(password.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(data, CC_LONG(data.count), &hash)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time comparison to prevent timing side-channel attacks
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        constantTimeEqual(Array(a), Array(b))
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }
        return result == 0
    }
}
