import Foundation
import Security
import CommonCrypto

public enum TLSTrustEvaluator {
    public static func evaluate(_ trust: SecTrust, profile: OperatorProfile) -> Bool {
        // Lab profiles may skip validation; production uses pinning or system trust.
        if profile.security.tls.allowInsecureLab {
            return true
        }

        let pins = profile.security.tls.pinnedCertificateSHA256
        if pins.isEmpty {
            var error: CFError?
            return SecTrustEvaluateWithError(trust, &error)
        }

        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return false
        }

        let digest = sha256Hex(certificate: leaf)
        return pins.map { $0.lowercased().replacingOccurrences(of: ":", with: "") }.contains(digest)
    }

    private static func sha256Hex(certificate: SecCertificate) -> String {
        let data = SecCertificateCopyData(certificate) as Data
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
