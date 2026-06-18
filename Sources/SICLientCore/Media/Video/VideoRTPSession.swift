import Foundation

public struct VideoMediaEndpoint: Sendable, Equatable {
    public var address: String
    public var port: Int
    public var payloadType: UInt8
    public var codec: VideoCodec

    public init(address: String, port: Int, payloadType: UInt8, codec: VideoCodec) {
        self.address = address
        self.port = port
        self.payloadType = payloadType
        self.codec = codec
    }
}

public actor VideoRTPSession {
    private var stats = RTPStreamStats()
    private var active = false

    public init() {}

    public func start(remote: VideoMediaEndpoint) async {
        active = true
        stats = RTPStreamStats()
        _ = remote
    }

    public func noteKeyframeSent(bytes: Int) {
        guard active else { return }
        stats.packetsSent &+= 1
        stats.bytesSent &+= UInt64(bytes)
    }

    public func currentStats() -> RTPStreamStats { stats }

    public func stop() async {
        active = false
    }
}
