import Foundation
import Security

// MARK: - File overview
//
// Creates the right SimAdapter for the current environment. A SIM (Subscriber Identity
// Module) holds IMS credentials: IMPI (IP Multimedia Private Identity) and IMPU
// (IP Multimedia Public Identity) URIs. Production devices read them from the macOS
// Keychain; lab profiles embed test vectors in the operator profile JSON.

/// Reads IMS credentials from macOS Keychain for production profiles without `lab_sim`.
public struct KeychainSimAdapter: SimAdapter {
    /// Keychain service name shared by all stored IMS credentials.
    public static let service = "com.siclient.imsi"

    private let account: String

    /// Opens credentials stored under the given Keychain account prefix.
    public init(account: String) {
        self.account = account
    }

    /// Returns the IMPI (private SIP identity, usually derived from the IMSI).
    public func getIMPI() throws -> String {
        try readCredential(key: "impi")
    }

    /// Returns all IMPU (public SIP URIs) as a comma-separated list from Keychain.
    public func getIMPUList() throws -> [String] {
        let raw = try readCredential(key: "impus")
        return raw.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// AKA challenges are not supported via Keychain — use a lab SIM adapter instead.
    public func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        _ = rand
        _ = autn
        throw SimAdapterError.unsupportedChallenge
    }

    /// Reads one UTF-8 credential string from the Keychain for this account.
    private func readCredential(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "\(account).\(key)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SimAdapterError.noCredentials
        }
        return value
    }
}

/// Chooses a SimAdapter based on profile config, Keychain env var, or unavailable fallback.
public enum SimAdapterFactory {
    /// Returns a lab SIM, Keychain SIM, or unavailable placeholder adapter.
    public static func make(profile: OperatorProfile) -> any SimAdapter {
        if let labSim = profile.labSim {
            return LabSimAdapter(config: labSim)
        }
        if let account = ProcessInfo.processInfo.environment["SICLIENT_KEYCHAIN_ACCOUNT"] {
            return KeychainSimAdapter(account: account)
        }
        return UnavailableSimAdapter()
    }
}

/// Placeholder that always reports missing credentials (no SIM or Keychain configured).
struct UnavailableSimAdapter: SimAdapter {
    func getIMPI() throws -> String { throw SimAdapterError.noCredentials }
    func getIMPUList() throws -> [String] { throw SimAdapterError.noCredentials }
    func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        throw SimAdapterError.noCredentials
    }
}
