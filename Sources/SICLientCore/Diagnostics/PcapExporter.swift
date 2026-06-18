import Foundation

public final class PcapExporter: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [Data] = []
    private let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func record(_ data: Data, direction: String) {
        guard enabled else { return }
        lock.withLock {
            var frame = Data()
            frame.append(Data(direction.utf8))
            frame.append(Data([0x00]))
            frame.append(data)
            packets.append(frame)
        }
    }

    public func export(to url: URL) throws {
        let snapshot = lock.withLock { packets }
        let payload = snapshot.reduce(into: Data()) { $0.append($1) }
        try payload.write(to: url, options: .atomic)
    }

    public func packetCount() -> Int {
        lock.withLock { packets.count }
    }
}

public struct RecordingSIPTransport: SIPTransport {
    public let isReliable: Bool
    private let inner: any SIPTransport
    private let exporter: PcapExporter
    private let direction: String

    public init(wrapping inner: any SIPTransport, exporter: PcapExporter, direction: String = "sip") {
        self.inner = inner
        self.exporter = exporter
        self.direction = direction
        self.isReliable = inner.isReliable
    }

    public func connect() async throws { try await inner.connect() }
    public func close() async { await inner.close() }

    public func send(_ data: Data) async throws {
        exporter.record(data, direction: "\(direction)-out")
        try await inner.send(data)
    }

    public func receive(timeout: Duration) async throws -> Data? {
        let data = try await inner.receive(timeout: timeout)
        if let data {
            exporter.record(data, direction: "\(direction)-in")
        }
        return data
    }
}
