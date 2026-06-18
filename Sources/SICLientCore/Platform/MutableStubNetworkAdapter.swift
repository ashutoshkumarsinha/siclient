import Foundation

// MARK: - File overview
//
// A thread-safe, mutable stub NetworkAdapter for tests. Simulates IP address and
// P-CSCF (Proxy Call Session Control Function) discovery changes — useful for
// handover and network-recovery scenarios.

/// Thread-safe stub network adapter whose local IP and path label can change at runtime.
public final class MutableStubNetworkAdapter: NetworkAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var localIP: String
    private var pathLabel: String
    private let resolvedHosts: [String: [String]]

    /// Creates a stub with default LTE path label and optional hostname overrides.
    public init(
        localIP: String = "127.0.0.1",
        pathLabel: String = "3GPP-E-UTRAN-FDD:234150999010203",
        resolvedHosts: [String: [String]] = [:]
    ) {
        self.localIP = localIP
        self.pathLabel = pathLabel
        self.resolvedHosts = resolvedHosts
    }

    /// Simulates a network change by updating local IP and access-network path label.
    public func setNetworkSnapshot(localIP: String, pathLabel: String) {
        lock.lock()
        self.localIP = localIP
        self.pathLabel = pathLabel
        lock.unlock()
    }

    /// Returns the current 3GPP access-network path label (for P-Access-Network-Info).
    public func currentPathLabel() -> String {
        lock.lock()
        defer { lock.unlock() }
        return pathLabel
    }

    /// Returns a static P-CSCF from the profile; PCO/DHCP modes are not supported here.
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

    /// Returns the current local IP address.
    public func localIPAddress() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return localIP
    }

    /// Looks up a hostname in the override table, or echoes the hostname back.
    public func resolveHostname(_ hostname: String) throws -> [String] {
        if let addresses = resolvedHosts[hostname] {
            return addresses
        }
        return [hostname]
    }
}
