import Foundation

// MARK: - File overview
//
// An in-memory SIP (Session Initiation Protocol) transport for unit tests. Outgoing
// messages are captured and passed to a responder closure that returns fake replies —
// no real network sockets are opened.

/// Actor-backed loopback transport that routes sent SIP messages through a responder.
public actor LoopbackSIPTransport: SIPTransport {
    public let isReliable: Bool
    private let responder: @Sendable (Data) -> [Data]
    private var inbox: [Data] = []
    private var outbox: [Data] = []

    /// Creates a transport with a responder that may return multiple SIP replies.
    public init(isReliable: Bool = true, responder: @escaping @Sendable (Data) -> [Data]) {
        self.isReliable = isReliable
        self.responder = responder
    }

    /// Convenience init for responders that return at most one reply per request.
    public init(isReliable: Bool = true, singleResponder: @escaping @Sendable (Data) -> Data?) {
        self.isReliable = isReliable
        self.responder = { data in
            guard let response = singleResponder(data) else { return [] }
            return [response]
        }
    }

    /// Inserts a message at the front of the receive queue (simulates an unsolicited message).
    public func requeue(_ data: Data) {
        inbox.insert(data, at: 0)
    }

    /// Appends a message to the receive queue (simulates an inbound message).
    public func inject(_ data: Data) {
        inbox.append(data)
    }

    /// Returns and clears all messages sent by the client since the last drain.
    public func drainSent() -> [Data] {
        let messages = outbox
        outbox.removeAll()
        return messages
    }

    /// No-op for loopback — there is no socket to open.
    public func connect() async throws {}

    /// Records the outgoing message and enqueues any responder replies.
    public func send(_ data: Data) async throws {
        outbox.append(data)
        inbox.append(contentsOf: responder(data))
    }

    /// Waits up to `timeout` for the next queued inbound message.
    public func receive(timeout: Duration) async throws -> Data? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !inbox.isEmpty {
                return inbox.removeFirst()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    /// Clears the receive queue.
    public func close() async {
        inbox.removeAll()
    }
}
