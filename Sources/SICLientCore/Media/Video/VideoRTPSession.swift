import Foundation

// MARK: - File Overview
// Lightweight video RTP (Real-time Transport Protocol) session tracker. Counts sent
// keyframes and bytes for video legs; full video encode/decode is not implemented here.

/// Network address and codec details for a video RTP stream.
public struct VideoMediaEndpoint: Sendable, Equatable {
    public var address: String
    public var port: Int
    public var payloadType: UInt8
    public var codec: VideoCodec

    /// Creates a remote video endpoint with IP, port, and codec parameters.
    public init(address: String, port: Int, payloadType: UInt8, codec: VideoCodec) {
        self.address = address
        self.port = port
        self.payloadType = payloadType
        self.codec = codec
    }
}

/// Tracks video RTP activity and statistics for a call leg.
public actor VideoRTPSession {
    private var stats = RTPStreamStats()
    private var active = false

    /// Creates an inactive video RTP session.
    public init() {}

    /// Marks the session active and resets statistics for a new remote endpoint.
    public func start(remote: VideoMediaEndpoint) async {
        active = true
        stats = RTPStreamStats()
        _ = remote
    }

    /// Records that a video keyframe of the given size was sent.
    public func noteKeyframeSent(bytes: Int) {
        guard active else { return }
        stats.packetsSent &+= 1
        stats.bytesSent &+= UInt64(bytes)
    }

    /// Returns current video stream statistics.
    public func currentStats() -> RTPStreamStats { stats }

    /// Deactivates the video session.
    public func stop() async {
        active = false
    }
}
