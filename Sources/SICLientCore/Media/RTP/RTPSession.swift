import Foundation

public struct RTPStreamStats: Sendable, Equatable {
    public var packetsSent: UInt64
    public var packetsReceived: UInt64
    public var bytesSent: UInt64
    public var bytesReceived: UInt64
    public var packetsLost: UInt64
    public var jitterMs: Double
    public var lastSequence: UInt16

    public init(
        packetsSent: UInt64 = 0,
        packetsReceived: UInt64 = 0,
        bytesSent: UInt64 = 0,
        bytesReceived: UInt64 = 0,
        packetsLost: UInt64 = 0,
        jitterMs: Double = 0,
        lastSequence: UInt16 = 0
    ) {
        self.packetsSent = packetsSent
        self.packetsReceived = packetsReceived
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.packetsLost = packetsLost
        self.jitterMs = jitterMs
        self.lastSequence = lastSequence
    }
}

public actor RTPSession {
    private let transport: any RTPTransport
    private let payloadType: UInt8
    private let clockRate: Int
    private var remote: MediaEndpoint?
    private var ssrc: UInt32 = UInt32.random(in: 1...UInt32.max)
    private var sequence: UInt16 = UInt16.random(in: 0...UInt16.max)
    private var timestamp: UInt32 = 0
    private var stats = RTPStreamStats()
    private var receiveTask: Task<Void, Never>?
    private var onPacket: (@Sendable (RTPPacket) -> Void)?

    public init(transport: any RTPTransport, payloadType: UInt8, clockRate: Int) {
        self.transport = transport
        self.payloadType = payloadType
        self.clockRate = clockRate
    }

    public func start(remote: MediaEndpoint, onPacket: @escaping @Sendable (RTPPacket) -> Void) async throws {
        self.remote = remote
        self.onPacket = onPacket
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    public func send(payload: Data, marker: Bool = false, samplesPerFrame: Int) async throws {
        guard let remote else { return }
        let packet = RTPPacket(
            marker: marker,
            payloadType: payloadType,
            sequenceNumber: sequence,
            timestamp: timestamp,
            ssrc: ssrc,
            payload: payload
        )
        try await transport.send(packet.serialize(), to: remote.address, port: remote.port)
        sequence &+= 1
        timestamp = timestamp &+ UInt32(samplesPerFrame)
        stats.packetsSent &+= 1
        stats.bytesSent &+= UInt64(payload.count)
    }

    public func sendRTCPReport() async throws {
        guard let remote else { return }
        let report = RTCPPacket.buildSenderReport(
            ssrc: ssrc,
            rtpTimestamp: timestamp,
            packetCount: UInt32(stats.packetsSent),
            octetCount: UInt32(stats.bytesSent)
        )
        try await transport.send(report, to: remote.address, port: remote.port + 1)
    }

    public func currentStats() -> RTPStreamStats { stats }

    public func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        remote = nil
        onPacket = nil
        await transport.close()
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                guard let received = try await transport.receive(timeout: .milliseconds(50)) else { continue }
                guard let packet = RTPPacket.parse(received.data) else { continue }
                guard packet.payloadType == payloadType else { continue }
                updateStats(packet)
                onPacket?(packet)
            } catch {
                continue
            }
        }
    }

    private func updateStats(_ packet: RTPPacket) {
        stats.packetsReceived &+= 1
        stats.bytesReceived &+= UInt64(packet.payload.count)
        if stats.lastSequence != 0 {
            let expected = stats.lastSequence &+ 1
            if packet.sequenceNumber > expected {
                stats.packetsLost &+= UInt64(packet.sequenceNumber - expected)
            }
            let delta = abs(Int32(packet.timestamp) - Int32(timestamp))
            let jitter = Double(delta) / Double(clockRate) * 1000.0
            stats.jitterMs = (stats.jitterMs * 0.9) + (jitter * 0.1)
        }
        stats.lastSequence = packet.sequenceNumber
    }
}
