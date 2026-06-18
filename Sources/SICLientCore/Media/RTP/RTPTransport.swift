import Foundation

public enum RTPTransportError: Error, Sendable, CustomStringConvertible {
    case notBound
    case sendFailed(String)
    case receiveFailed(String)

    public var description: String {
        switch self {
        case .notBound: return "RTP transport is not bound"
        case .sendFailed(let reason): return "RTP send failed: \(reason)"
        case .receiveFailed(let reason): return "RTP receive failed: \(reason)"
        }
    }
}

public protocol RTPTransport: Sendable {
    func bind(localPort: Int) async throws
    func send(_ data: Data, to host: String, port: Int) async throws
    func receive(timeout: Duration) async throws -> (data: Data, host: String, port: Int)?
    func close() async
}

public actor LoopbackRTPBridge {
    private var leftInbox: [Data] = []
    private var rightInbox: [Data] = []

    public init() {}

    public func sendLeftToRight(_ data: Data) {
        rightInbox.append(data)
    }

    public func sendRightToLeft(_ data: Data) {
        leftInbox.append(data)
    }

    public func receiveLeft(timeout: Duration) async -> Data? {
        await dequeueLeft(timeout: timeout)
    }

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

public final class LoopbackRTPTransport: RTPTransport, @unchecked Sendable {
    private let bridge: LoopbackRTPBridge
    private let isLeftSide: Bool
    private var localPort: Int = 0
    private var remoteHost = "127.0.0.1"
    private var remotePort = 0

    public init(bridge: LoopbackRTPBridge, isLeftSide: Bool) {
        self.bridge = bridge
        self.isLeftSide = isLeftSide
    }

    public func bind(localPort: Int) async throws {
        self.localPort = localPort
    }

    public func setPeer(host: String, port: Int) async {
        remoteHost = host
        remotePort = port
    }

    public func send(_ data: Data, to host: String, port: Int) async throws {
        if isLeftSide {
            await bridge.sendLeftToRight(data)
        } else {
            await bridge.sendRightToLeft(data)
        }
    }

    public func receive(timeout: Duration) async throws -> (data: Data, host: String, port: Int)? {
        let data = isLeftSide
            ? await bridge.receiveLeft(timeout: timeout)
            : await bridge.receiveRight(timeout: timeout)
        guard let data else { return nil }
        return (data, remoteHost, remotePort)
    }

    public func close() async {}
}
