import Foundation
import Network

// MARK: - File overview
//
// Real and factory-built SIP (Session Initiation Protocol) transports over UDP,
// TCP, and TLS (Transport Layer Security). These send and receive raw SIP message
// bytes to/from the P-CSCF (Proxy Call Session Control Function).

/// Errors that can occur while connecting, sending, or receiving SIP messages.
public enum SIPTransportError: Error, Sendable, CustomStringConvertible {
    case notConnected
    case sendFailed(String)
    case receiveFailed(String)
    case bindFailed(String)

    public var description: String {
        switch self {
        case .notConnected: return "SIP transport is not connected"
        case .sendFailed(let reason): return "SIP send failed: \(reason)"
        case .receiveFailed(let reason): return "SIP receive failed: \(reason)"
        case .bindFailed(let reason): return "SIP bind failed: \(reason)"
        }
    }
}

/// Common interface for sending and receiving SIP messages over any underlying protocol.
public protocol SIPTransport: Sendable {
    /// True for TCP/TLS (messages arrive in order); false for UDP.
    var isReliable: Bool { get }
    /// Opens the connection to the P-CSCF endpoint.
    func connect() async throws
    /// Sends a complete SIP message as raw bytes.
    func send(_ data: Data) async throws
    /// Waits up to `timeout` for an inbound SIP message; nil on timeout.
    func receive(timeout: Duration) async throws -> Data?
    /// Tears down the connection and releases resources.
    func close() async
}

/// Connectionless SIP transport over UDP (User Datagram Protocol).
public final class UDPTransport: SIPTransport, @unchecked Sendable {
    public let isReliable = false
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "siclient.udp")

    /// Targets the given P-CSCF host and port.
    public init(host: String, port: Int) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(integerLiteral: UInt16(port))
    }

    /// Starts the UDP connection and waits until the network stack reports ready.
    public func connect() async throws {
        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SIPTransportError.bindFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Sends one SIP datagram; UDP does not guarantee delivery.
    public func send(_ data: Data) async throws {
        guard let connection else { throw SIPTransportError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: SIPTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Waits for the next UDP datagram or times out.
    public func receive(timeout: Duration) async throws -> Data? {
        guard let connection else { throw SIPTransportError.notConnected }
        // Race receive against a sleep task so callers get nil on timeout
        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    connection.receiveMessage { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: SIPTransportError.receiveFailed(error.localizedDescription))
                        } else {
                            continuation.resume(returning: data)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Cancels the UDP connection.
    public func close() async {
        connection?.cancel()
        connection = nil
    }
}

/// Reliable SIP transport over TCP (Transmission Control Protocol).
public final class TCPTransport: SIPTransport, @unchecked Sendable {
    public let isReliable = true
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "siclient.tcp")
    private var buffer = Data()

    /// Targets the given P-CSCF host and port over TCP.
    public init(host: String, port: Int) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(integerLiteral: UInt16(port))
    }

    /// Opens a TCP connection to the P-CSCF.
    public func connect() async throws {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SIPTransportError.bindFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Sends a complete SIP message over the TCP stream.
    public func send(_ data: Data) async throws {
        guard let connection else { throw SIPTransportError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: SIPTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Reads from the TCP stream until one full SIP message is assembled or timeout.
    public func receive(timeout: Duration) async throws -> Data? {
        guard connection != nil else { throw SIPTransportError.notConnected }

        if let message = try extractMessage() {
            return message
        }

        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    self.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: SIPTransportError.receiveFailed(error.localizedDescription))
                            return
                        }
                        if let data {
                            self.buffer.append(data)
                        }
                        do {
                            continuation.resume(returning: try self.extractMessage())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Closes TCP and clears the reassembly buffer.
    public func close() async {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    /// Pulls one SIP message from the buffer when headers + body are complete.
    private func extractMessage() throws -> Data? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<range.upperBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let contentLength = headerText
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0

        let total = range.upperBound + contentLength
        guard buffer.count >= total else { return nil } // Body not fully received yet
        let message = buffer[..<total]
        buffer.removeSubrange(..<total)
        return Data(message)
    }
}

/// Encrypted SIP transport over TLS on top of TCP.
public final class TLSTransport: SIPTransport, @unchecked Sendable {
    public let isReliable = true
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let profile: OperatorProfile
    private let hostname: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "siclient.tls")
    private var buffer = Data()

    /// Targets the P-CSCF with TLS certificate validation from the operator profile.
    public init(host: String, port: Int, profile: OperatorProfile) {
        self.hostname = host
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(integerLiteral: UInt16(port))
        self.profile = profile
    }

    /// Opens a TLS connection with pinning or lab-trust rules from the profile.
    public func connect() async throws {
        let tlsOptions = NWProtocolTLS.Options()
        let tlsProfile = profile
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, complete in
                let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
                complete(TLSTrustEvaluator.evaluate(trustRef, profile: tlsProfile))
            },
            queue
        )

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SIPTransportError.bindFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    /// Sends a SIP message over the encrypted TLS stream.
    public func send(_ data: Data) async throws {
        guard let connection else { throw SIPTransportError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: SIPTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Reads from TLS until one complete SIP message is available or timeout.
    public func receive(timeout: Duration) async throws -> Data? {
        guard connection != nil else { throw SIPTransportError.notConnected }

        if let message = try extractMessage() {
            return message
        }

        return try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                    self.connection?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, _, _, error in
                        if let error {
                            continuation.resume(throwing: SIPTransportError.receiveFailed(error.localizedDescription))
                            return
                        }
                        if let data {
                            self.buffer.append(data)
                        }
                        do {
                            continuation.resume(returning: try self.extractMessage())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Closes TLS and clears the reassembly buffer.
    public func close() async {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    /// Pulls one SIP message from the buffer when headers + body are complete.
    private func extractMessage() throws -> Data? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[..<range.upperBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let contentLength = headerText
            .split(separator: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0

        let total = range.upperBound + contentLength
        guard buffer.count >= total else { return nil }
        let message = buffer[..<total]
        buffer.removeSubrange(..<total)
        return Data(message)
    }
}

/// Builds the right SIPTransport for a P-CSCF endpoint, with optional UDP fallback.
public enum TransportFactory {
    /// Creates UDP/TCP/TLS transport, wrapping UDP in FallbackSIPTransport when configured.
    public static func make(endpoint: PCSCFEndpoint, profile: OperatorProfile) -> any SIPTransport {
        let primary = makeSingle(endpoint: endpoint, transport: endpoint.transport, profile: profile)

        if endpoint.transport == .udp,
           TransportPolicy.fallbackProtocol(for: profile.transport.preference, current: .udp) != nil,
           let fallbackProtocol = TransportPolicy.fallbackProtocol(for: profile.transport.preference, current: .udp) {
            let fallbackEndpoint = PCSCFEndpoint(host: endpoint.host, port: endpoint.port, transport: fallbackProtocol)
            let fallback = makeSingle(endpoint: fallbackEndpoint, transport: fallbackProtocol, profile: profile)
            return FallbackSIPTransport(
                primary: primary,
                fallback: fallback,
                mtuLimit: profile.resilience.mtuBytes
            )
        }

        return primary
    }

    /// Instantiates a single transport without fallback wrapping.
    private static func makeSingle(endpoint: PCSCFEndpoint, transport: TransportProtocol, profile: OperatorProfile) -> any SIPTransport {
        switch transport {
        case .udp:
            return UDPTransport(host: endpoint.host, port: endpoint.port)
        case .tcp:
            return TCPTransport(host: endpoint.host, port: endpoint.port)
        case .tls:
            return TLSTransport(host: endpoint.host, port: endpoint.port, profile: profile)
        }
    }
}
