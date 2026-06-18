import Foundation

public struct PCSCFEndpoint: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let transport: TransportProtocol

    public init(host: String, port: Int, transport: TransportProtocol) {
        self.host = host
        self.port = port
        self.transport = transport
    }
}

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

public protocol NetworkAdapter: Sendable {
    func discoverPCSCF(profile: OperatorProfile) throws -> PCSCFEndpoint
    func localIPAddress() throws -> String
    func resolveHostname(_ hostname: String) throws -> [String]
}
