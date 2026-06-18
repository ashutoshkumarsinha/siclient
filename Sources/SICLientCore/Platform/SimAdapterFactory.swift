import Foundation
import Security

/// Reads IMS credentials from macOS Keychain for production profiles without `lab_sim`.
public struct KeychainSimAdapter: SimAdapter {
    public static let service = "com.siclient.imsi"

    private let account: String

    public init(account: String) {
        self.account = account
    }

    public func getIMPI() throws -> String {
        try readCredential(key: "impi")
    }

    public func getIMPUList() throws -> [String] {
        let raw = try readCredential(key: "impus")
        return raw.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
    }

    public func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        _ = rand
        _ = autn
        throw SimAdapterError.unsupportedChallenge
    }

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

public enum SimAdapterFactory {
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

struct UnavailableSimAdapter: SimAdapter {
    func getIMPI() throws -> String { throw SimAdapterError.noCredentials }
    func getIMPUList() throws -> [String] { throw SimAdapterError.noCredentials }
    func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        throw SimAdapterError.noCredentials
    }
}
