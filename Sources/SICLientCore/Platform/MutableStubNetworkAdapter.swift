import Foundation

public final class MutableStubNetworkAdapter: NetworkAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var localIP: String
    private var pathLabel: String
    private let resolvedHosts: [String: [String]]

    public init(
        localIP: String = "127.0.0.1",
        pathLabel: String = "3GPP-E-UTRAN-FDD:234150999010203",
        resolvedHosts: [String: [String]] = [:]
    ) {
        self.localIP = localIP
        self.pathLabel = pathLabel
        self.resolvedHosts = resolvedHosts
    }

    public func setNetworkSnapshot(localIP: String, pathLabel: String) {
        lock.lock()
        self.localIP = localIP
        self.pathLabel = pathLabel
        lock.unlock()
    }

    public func currentPathLabel() -> String {
        lock.lock()
        defer { lock.unlock() }
        return pathLabel
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
        lock.lock()
        defer { lock.unlock() }
        return localIP
    }

    public func resolveHostname(_ hostname: String) throws -> [String] {
        if let addresses = resolvedHosts[hostname] {
            return addresses
        }
        return [hostname]
    }
}
