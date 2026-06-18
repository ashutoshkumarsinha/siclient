import Foundation

// MARK: - File overview
//
// A simple NetworkAdapter for tests and lab setups. It reads P-CSCF (Proxy Call Session
// Control Function) addresses from the operator profile instead of performing real DNS
// or modem PCO/DHCP discovery.

/// Test network adapter that resolves P-CSCF from profile config and fixed local IP.
public struct StubNetworkAdapter: NetworkAdapter {
    private let localIP: String
    private let resolvedHosts: [String: [String]]

    /// Creates a stub with a fake local IP and optional hostname-to-IP overrides.
    public init(localIP: String = "127.0.0.1", resolvedHosts: [String: [String]] = [:]) {
        self.localIP = localIP
        self.resolvedHosts = resolvedHosts
    }

    /// Returns a static P-CSCF from the profile, or parses PCO/DHCP address lists.
    public func discoverPCSCF(profile: OperatorProfile) throws -> PCSCFEndpoint {
        switch profile.pcscf.mode {
        case .static:
            guard
                let host = profile.pcscf.address,
                let port = profile.pcscf.port,
                let transport = profile.transport.preference.first
            else {
                throw NetworkAdapterError.discoveryUnavailable
            }
            return PCSCFEndpoint(host: host, port: port, transport: transport)
        case .pco, .dhcp:
            return try PCSCFDiscovery.endpoint(from: profile, resolver: self)
        }
    }

    /// Returns the configured local IP (used in SIP Contact headers).
    public func localIPAddress() throws -> String {
        localIP
    }

    /// Looks up a hostname in the override table, or echoes the hostname back.
    public func resolveHostname(_ hostname: String) throws -> [String] {
        if let addresses = resolvedHosts[hostname] {
            return addresses
        }
        return [hostname]
    }
}
