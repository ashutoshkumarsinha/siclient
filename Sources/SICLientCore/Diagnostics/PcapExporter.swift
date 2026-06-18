import Foundation

// MARK: - File Overview
// Records SIP (Session Initiation Protocol) traffic to a file for offline analysis.
// Also provides a wrapping SIP transport that captures every sent and received message.

/// Collects raw packet bytes and exports them to a file (lab pcap-style format).
public final class PcapExporter: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [Data] = []
    private let enabled: Bool

    /// Creates an exporter; recording is a no-op when disabled.
    public init(enabled: Bool) {
        self.enabled = enabled
    }

    /// Records one packet prefixed with a direction label (e.g. "sip-out").
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

    /// Writes all recorded packets to a file at the given URL.
    public func export(to url: URL) throws {
        let snapshot = lock.withLock { packets }
        let payload = snapshot.reduce(into: Data()) { $0.append($1) }
        try payload.write(to: url, options: .atomic)
    }

    /// Returns how many packets have been recorded so far.
    public func packetCount() -> Int {
        lock.withLock { packets.count }
    }
}

/// SIP transport wrapper that records all traffic through a PcapExporter.
public struct RecordingSIPTransport: SIPTransport {
    public let isReliable: Bool
    private let inner: any SIPTransport
    private let exporter: PcapExporter
    private let direction: String

    /// Wraps an inner transport and records every send/receive to the exporter.
    public init(wrapping inner: any SIPTransport, exporter: PcapExporter, direction: String = "sip") {
        self.inner = inner
        self.exporter = exporter
        self.direction = direction
        self.isReliable = inner.isReliable
    }

    /// Connects the inner transport.
    public func connect() async throws { try await inner.connect() }

    /// Closes the inner transport.
    public func close() async { await inner.close() }

    /// Records outgoing data then forwards to the inner transport.
    public func send(_ data: Data) async throws {
        exporter.record(data, direction: "\(direction)-out")
        try await inner.send(data)
    }

    /// Receives data from the inner transport and records it before returning.
    public func receive(timeout: Duration) async throws -> Data? {
        let data = try await inner.receive(timeout: timeout)
        if let data {
            exporter.record(data, direction: "\(direction)-in")
        }
        return data
    }
}
