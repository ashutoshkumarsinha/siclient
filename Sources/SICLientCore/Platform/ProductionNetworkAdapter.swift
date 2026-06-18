import Foundation

// MARK: - File overview
//
// Production implementation of NetworkAdapter for real deployments. It discovers the
// P-CSCF (Proxy Call Session Control Function) using static config, PCO (Protocol
// Configuration Options), DHCP (Dynamic Host Configuration Protocol), or DNS SRV records,
// and reports the device's local IP address.

/// Production network adapter: static, PCO, DHCP, and DNS SRV discovery hooks.
public struct ProductionNetworkAdapter: NetworkAdapter {
    private let localIP: String
    private let srvRecords: [String: [IMSDNSResolver.SRVRecord]]
    private let resolvedHosts: [String: [String]]

    /// Creates an adapter with optional injected DNS/hostname data (useful for testing bridges).
    public init(
        localIP: String = "127.0.0.1",
        srvRecords: [String: [IMSDNSResolver.SRVRecord]] = [:],
        resolvedHosts: [String: [String]] = [:]
    ) {
        self.localIP = localIP
        self.srvRecords = srvRecords
        self.resolvedHosts = resolvedHosts
    }

    /// Discovers P-CSCF via static address, PCO list, or DHCP list from the profile.
    public func discoverPCSCF(profile: OperatorProfile) throws -> PCSCFEndpoint {
        if profile.pcscf.mode == .static || profile.pcscf.mode == .pco || profile.pcscf.mode == .dhcp {
            return try PCSCFDiscovery.endpoint(from: profile, resolver: self)
        }
        throw NetworkAdapterError.discoveryUnavailable
    }

    /// Discovers P-CSCF via DNS SRV lookup using pre-resolved records.
    public func discoverPCSCFViaDNS(profile: OperatorProfile) throws -> PCSCFEndpoint {
        let domain = profile.pcscf.dnsDomain ?? profile.homeDomain
        let key = "_sip._udp.\(domain)"
        if let records = srvRecords[key] {
            return try PCSCFDiscovery.endpointFromDNS(profile: profile, srvRecords: records)
        }
        throw NetworkAdapterError.discoveryUnavailable
    }

    /// Returns this device's local IP address used in SIP Contact headers.
    public func localIPAddress() throws -> String {
        localIP
    }

    /// Resolves a hostname to IP addresses; returns the hostname itself if not in the lookup table.
    public func resolveHostname(_ hostname: String) throws -> [String] {
        if let addresses = resolvedHosts[hostname] {
            return addresses
        }
        return [hostname]
    }
}

extension ProductionNetworkAdapter {
    /// Picks ProductionNetworkAdapter when PCO/DHCP discovery is configured; otherwise uses a stub.
    public static func forProfile(_ profile: OperatorProfile) -> any NetworkAdapter {
        if profile.pcscf.mode == .pco || profile.pcscf.mode == .dhcp {
            return ProductionNetworkAdapter()
        }
        return StubNetworkAdapter()
    }
}
