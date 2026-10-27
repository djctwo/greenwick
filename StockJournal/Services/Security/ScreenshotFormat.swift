import CryptoKit
import Foundation

/// File format of a sealed trade screenshot:
/// "GWSC" | version (1 byte) | AES-GCM nonce | ciphertext | tag.
///
/// The image is sealed with the journal's key (AES-256-GCM). The header and the file's own
/// name are AES-GCM associated data, so a file can't be passed off under another name or
/// version: it then fails to open. Files without the "GWSC" magic are plain images saved by
/// Greenwick versions before screenshots were encrypted (`ScreenshotManager.sealLegacyFiles`).
enum ScreenshotFormat {
    static let magic = Data("GWSC".utf8)
    static let version: UInt8 = 1
    static let header = magic + Data([version])

    /// Whether `file` starts like a sealed screenshot (any version)
    static func isSealed(_ file: Data) -> Bool {
        file.count >= magic.count && file.prefix(magic.count) == magic
    }

    /// Seal `image` for the file called `name`
    static func seal(_ image: Data, key: SymmetricKey, name: String) throws -> Data {
        let box = try AES.GCM.seal(image, using: key, authenticating: associatedData(name))
        guard let combined = box.combined else { throw DatabaseEncryption.EncryptionError.encryptionFailed }
        return header + combined
    }

    /// The image inside `file` (named `name`). Throws `decryptionFailed` for another key, a
    /// changed byte, another name or an unknown version.
    static func open(_ file: Data, key: SymmetricKey, name: String) throws -> Data {
        guard file.count > header.count, file.prefix(header.count) == header else {
            throw DatabaseEncryption.EncryptionError.decryptionFailed
        }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(file.dropFirst(header.count)))
            return try AES.GCM.open(box, using: key, authenticating: associatedData(name))
        } catch {
            throw DatabaseEncryption.EncryptionError.decryptionFailed
        }
    }

    private static func associatedData(_ name: String) -> Data {
        header + Data(name.utf8)
    }
}
