import Foundation

/// Production network adapter: static, PCO, DHCP, and DNS SRV discovery hooks.
public struct ProductionNetworkAdapter: NetworkAdapter {
    private let localIP: String
    private let srvRecords: [String: [IMSDNSResolver.SRVRecord]]
    private let resolvedHosts: [String: [String]]

    public init(
        localIP: String = "127.0.0.1",
        srvRecords: [String: [IMSDNSResolver.SRVRecord]] = [:],
        resolvedHosts: [String: [String]] = [:]
    ) {
        self.localIP = localIP
        self.srvRecords = srvRecords
        self.resolvedHosts = resolvedHosts
    }

    public func discoverPCSCF(profile: OperatorProfile) throws -> PCSCFEndpoint {
        if profile.pcscf.mode == .static || profile.pcscf.mode == .pco || profile.pcscf.mode == .dhcp {
            return try PCSCFDiscovery.endpoint(from: profile, resolver: self)
        }
        throw NetworkAdapterError.discoveryUnavailable
    }

    public func discoverPCSCFViaDNS(profile: OperatorProfile) throws -> PCSCFEndpoint {
        let domain = profile.pcscf.dnsDomain ?? profile.homeDomain
        let key = "_sip._udp.\(domain)"
        if let records = srvRecords[key] {
            return try PCSCFDiscovery.endpointFromDNS(profile: profile, srvRecords: records)
        }
        throw NetworkAdapterError.discoveryUnavailable
    }

    public func localIPAddress() throws -> String {
        localIP
    }

    public func resolveHostname(_ hostname: String) throws -> [String] {
        if let addresses = resolvedHosts[hostname] {
            return addresses
        }
        return [hostname]
    }
}

extension ProductionNetworkAdapter {
    /// Convenience factory used by bootstrap when PCO/DHCP env or profile lists are present.
    public static func forProfile(_ profile: OperatorProfile) -> any NetworkAdapter {
        if profile.pcscf.mode == .pco || profile.pcscf.mode == .dhcp {
            return ProductionNetworkAdapter()
        }
        return StubNetworkAdapter()
    }
}
