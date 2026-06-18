import Foundation

// MARK: - File overview
//
// Defines how the client discovers the P-CSCF (Proxy Call Session Control Function) —
// the first SIP (Session Initiation Protocol) hop in an IMS (IP Multimedia Subsystem)
// network — and obtains local IP / DNS information.

/// A resolved P-CSCF server: hostname, port, and SIP transport protocol.
public struct PCSCFEndpoint: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let transport: TransportProtocol

    /// Creates an endpoint from discovery results.
    public init(host: String, port: Int, transport: TransportProtocol) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}

/// Errors raised when P-CSCF discovery or local address lookup fails.
public enum NetworkAdapterError: Error, Sendable, CustomStringConvertible {
    case discoveryUnavailable
    case noLocalAddress

    public var description: String {
        switch self {
        case .discoveryUnavailable:
            return "P-CSCF discovery is not available"
        case .noLocalAddress:
            return "No local IP address is available"
        }
    }
}

/// Platform hook for P-CSCF discovery, local IP, and hostname resolution.
public protocol NetworkAdapter: Sendable {
    /// Finds the P-CSCF address using the profile's discovery mode.
    func discoverPCSCF(profile: OperatorProfile) throws -> PCSCFEndpoint
    /// Returns this device's IP address for SIP Contact headers.
    func localIPAddress() throws -> String
    /// Resolves a hostname to one or more IP address strings.
    func resolveHostname(_ hostname: String) throws -> [String]
}
