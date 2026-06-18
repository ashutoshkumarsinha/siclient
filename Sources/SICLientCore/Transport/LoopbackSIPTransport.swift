import Foundation

public actor LoopbackSIPTransport: SIPTransport {
    public let isReliable: Bool
    private let responder: @Sendable (Data) -> [Data]
    private var inbox: [Data] = []
    private var outbox: [Data] = []

    public init(isReliable: Bool = true, responder: @escaping @Sendable (Data) -> [Data]) {
        self.isReliable = isReliable
        self.responder = responder
    }

    public init(isReliable: Bool = true, singleResponder: @escaping @Sendable (Data) -> Data?) {
        self.isReliable = isReliable
        self.responder = { data in
            guard let response = singleResponder(data) else { return [] }
            return [response]
        }
    }

    public func requeue(_ data: Data) {
        inbox.insert(data, at: 0)
    }

    public func inject(_ data: Data) {
        inbox.append(data)
    }

    public func drainSent() -> [Data] {
        let messages = outbox
        outbox.removeAll()
        return messages
    }

    public func connect() async throws {}

    public func send(_ data: Data) async throws {
        outbox.append(data)
        inbox.append(contentsOf: responder(data))
    }

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

    public func close() async {
        inbox.removeAll()
    }
}
