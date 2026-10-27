import CryptoKit
import Foundation
import os
import Security

/// Public key pinning delegate for URLSession.
///
/// For the two services Greenwick talks to (Anthropic and Finnhub), the server's
/// certificate chain must pass normal system validation AND contain a certificate
/// issued under Google Trust Services, the CA both services use. Pins are SHA-256
/// hashes of the DER-encoded SubjectPublicKeyInfo (same as
/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`).
///
/// Only CA-level keys are pinned (no leaf certificates), so routine certificate
/// renewals don't break the app. If a service moves to a different CA, these pins
/// must be updated, otherwise requests to that host fail closed.
/// Every other host gets standard system TLS validation.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {
    private static let logger = Logger(subsystem: "com.greenwick", category: "CertPinning")

    // MARK: - Pin Registry

    /// Hosts whose certificate chain must match one of `caPins`.
    private static let pinnedHosts: Set<String> = [
        "api.anthropic.com",
        "finnhub.io",
    ]

    /// Google Trust Services keys (checked 2026-10-26; roots valid until 2036).
    private static let caPins: Set<String> = [
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=", // WE1 intermediate
        "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=", // GTS Root R1
        "Vfd95BwDeSQo+NUYxVEEIlvkOlWY2SalKK1lPhzOx78=", // GTS Root R2
        "QXnt2YHvdHR3tJYmQIr0Paosp6t/nggsEGD4QJZ3Q0g=", // GTS Root R3
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=", // GTS Root R4
    ]

    /// Shared singleton — delegate is stateless and Sendable
    static let shared = CertificatePinningDelegate()

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // If host isn't in our pin list, use default system validation
        guard Self.pinnedHosts.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the trust chain first (system validation)
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            Self.logger.error("Certificate trust evaluation failed for \(host): \(error.debugDescription)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let allPins = Self.caPins

        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            Self.logger.error("Failed to extract certificate chain for \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        for (i, certificate) in chain.enumerated() {
            if let publicKeyHash = Self.sha256HashOfPublicKey(for: certificate),
               allPins.contains(publicKeyHash) {
                Self.logger.debug("Pin matched for \(host) (cert \(i))")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        Self.logger.error("Certificate pinning failed for \(host) — no matching pin in chain")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Public Key Hashing

    /// SPKI headers for reconstructing DER-encoded SubjectPublicKeyInfo from raw key bytes.
    /// SecKeyCopyExternalRepresentation returns raw key data; openssl hashes the full SPKI structure.
    /// We prepend the appropriate ASN.1 header so our hashes match openssl-generated pins.
    private static let ecP256SPKIHeader = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ])

    private static let ecP384SPKIHeader = Data([
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
        0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ])

    private static let rsa2048SPKIHeader = Data([
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7,
        0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00
    ])

    private static let rsa4096SPKIHeader = Data([
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7,
        0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0F, 0x00
    ])

    /// Extract the public key from a certificate and return its SHA-256 hash (base64).
    /// Hashes the full SPKI (SubjectPublicKeyInfo) DER structure to match openssl-generated pins.
    private static func sha256HashOfPublicKey(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }

        var error: Unmanaged<CFError>?
        guard let rawKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Determine key type and select appropriate SPKI header
        let spkiHeader: Data
        let keyType = SecKeyCopyAttributes(publicKey) as? [String: Any]
        let type = keyType?[kSecAttrKeyType as String] as? String

        if type == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            spkiHeader = rawKeyData.count <= 65 ? ecP256SPKIHeader : ecP384SPKIHeader
        } else {
            spkiHeader = rawKeyData.count <= 270 ? rsa2048SPKIHeader : rsa4096SPKIHeader
        }

        var spkiData = spkiHeader
        spkiData.append(rawKeyData)

        let hash = SHA256.hash(data: spkiData)
        return Data(hash).base64EncodedString()
    }
}

// MARK: - Factory

extension CertificatePinningDelegate {
    /// Create a URLSession with certificate pinning and standard security configuration
    static func pinnedSession(timeout: TimeInterval = 30) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(
            configuration: config,
            delegate: shared,
            delegateQueue: nil
        )
    }
}
