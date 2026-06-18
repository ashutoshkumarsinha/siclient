import Foundation

// MARK: - File Overview
// Defines the RTP (Real-time Transport Protocol) transport interface and a loopback
// implementation for testing two call legs in-process without real network I/O.

/// Errors that can occur when binding, sending, or receiving RTP packets.
public enum RTPTransportError: Error, Sendable, CustomStringConvertible {
    case notBound
    case sendFailed(String)
    case receiveFailed(String)

    /// Human-readable error description.
    public var description: String {
        switch self {
        case .notBound: return "RTP transport is not bound"
        case .sendFailed(let reason): return "RTP send failed: \(reason)"
        case .receiveFailed(let reason): return "RTP receive failed: \(reason)"
        }
    }
}

/// Contract for sending and receiving raw RTP/RTCP bytes over the network or loopback.
public protocol RTPTransport: Sendable {
    /// Binds a local port for receiving packets.
    func bind(localPort: Int) async throws
    /// Sends raw bytes to the given host and port.
    func send(_ data: Data, to host: String, port: Int) async throws
    /// Waits up to `timeout` for the next received packet.
    func receive(timeout: Duration) async throws -> (data: Data, host: String, port: Int)?
    /// Releases transport resources.
    func close() async
}

/// In-memory bridge that forwards RTP packets between two loopback transport sides.
public actor LoopbackRTPBridge {
    private var leftInbox: [Data] = []
    private var rightInbox: [Data] = []

    /// Creates an empty loopback bridge.
    public init() {}

    /// Delivers a packet from the left side to the right side's inbox.
    public func sendLeftToRight(_ data: Data) {
        rightInbox.append(data)
    }

    /// Delivers a packet from the right side to the left side's inbox.
    public func sendRightToLeft(_ data: Data) {
        leftInbox.append(data)
    }

    /// Waits for the next packet addressed to the left side.
    public func receiveLeft(timeout: Duration) async -> Data? {
        await dequeueLeft(timeout: timeout)
    }

    /// Waits for the next packet addressed to the right side.
    public func receiveRight(timeout: Duration) async -> Data? {
        await dequeueRight(timeout: timeout)
    }

    private func dequeueLeft(timeout: Duration) async -> Data? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !leftInbox.isEmpty { return leftInbox.removeFirst() }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    private func dequeueRight(timeout: Duration) async -> Data? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !rightInbox.isEmpty { return rightInbox.removeFirst() }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }
}

/// RTP transport that delivers packets through a shared in-memory bridge (no UDP).
public final class LoopbackRTPTransport: RTPTransport, @unchecked Sendable {
    private let bridge: LoopbackRTPBridge
    private let isLeftSide: Bool
    private var localPort: Int = 0
    private var remoteHost = "127.0.0.1"
    private var remotePort = 0

    /// Creates a loopback transport on one side of the bridge.
    public init(bridge: LoopbackRTPBridge, isLeftSide: Bool) {
        self.bridge = bridge
        self.isLeftSide = isLeftSide
    }

    /// Records the local port (no real socket binding in loopback mode).
    public func bind(localPort: Int) async throws {
        self.localPort = localPort
    }

    /// Sets the peer address returned with received packets.
    public func setPeer(host: String, port: Int) async {
        remoteHost = host
        remotePort = port
    }

    /// Forwards the packet to the opposite side of the loopback bridge.
    public func send(_ data: Data, to host: String, port: Int) async throws {
        if isLeftSide {
            await bridge.sendLeftToRight(data)
        } else {
            await bridge.sendRightToLeft(data)
        }
    }

    /// Waits for the next packet from the opposite side of the bridge.
    public func receive(timeout: Duration) async throws -> (data: Data, host: String, port: Int)? {
        let data = isLeftSide
            ? await bridge.receiveLeft(timeout: timeout)
            : await bridge.receiveRight(timeout: timeout)
        guard let data else { return nil }
        return (data, remoteHost, remotePort)
    }

    /// No-op close for loopback transport.
    public func close() async {}
}
