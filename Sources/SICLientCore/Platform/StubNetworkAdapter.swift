import Foundation

public struct StubNetworkAdapter: NetworkAdapter {
    private let localIP: String
    private let resolvedHosts: [String: [String]]

    public init(localIP: String = "127.0.0.1", resolvedHosts: [String: [String]] = [:]) {
        self.localIP = localIP
        self.resolvedHosts = resolvedHosts
    }

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
            throw NetworkAdapterError.discoveryUnavailable
        }
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
