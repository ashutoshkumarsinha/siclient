import Foundation
import Network

private actor UDPInbox {
    private var items: [(data: Data, host: String, port: Int)] = []

    func enqueue(_ item: (data: Data, host: String, port: Int)) {
        items.append(item)
    }

    func dequeue() -> (data: Data, host: String, port: Int)? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    func clear() {
        items.removeAll()
    }
}

public final class UDPRTPTransport: RTPTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "siclient.rtp.udp")
    private var listener: NWListener?
    private var boundPort: Int = 0
    private let inbox = UDPInbox()

    public init() {}

    public func bind(localPort: Int) async throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let listener: NWListener
        if localPort == 0 {
            listener = try NWListener(using: params)
        } else {
            guard let port = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
                throw RTPTransportError.notBound
            }
            listener = try NWListener(using: params, on: port)
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        self?.boundPort = Int(port)
                    }
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: RTPTransportError.sendFailed(error.localizedDescription))
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        }
    }

    public func send(_ data: Data, to host: String, port: Int) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw RTPTransportError.sendFailed("invalid port \(port)")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            continuation.resume(throwing: RTPTransportError.sendFailed(error.localizedDescription))
                        } else {
                            continuation.resume()
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    continuation.resume(throwing: RTPTransportError.sendFailed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func receive(timeout: Duration) async throws -> (data: Data, host: String, port: Int)? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let item = await inbox.dequeue() {
                return item
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    public func close() async {
        listener?.cancel()
        listener = nil
        await inbox.clear()
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                var host = "127.0.0.1"
                var port = 0
                if case let .hostPort(h, p) = connection.endpoint {
                    host = "\(h)"
                    port = Int(p.rawValue)
                }
                Task { await self.inbox.enqueue((data, host, port)) }
            }
            if error == nil {
                self.receive(on: connection)
            }
        }
    }
}
