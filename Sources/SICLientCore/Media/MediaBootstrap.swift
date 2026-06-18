import Foundation

// MARK: - File Overview
// Wires up media components (RTP transport and audio codec engines) based on the
// operator profile. Think of this as a factory that picks the right building blocks
// for a VoLTE media session.

/// Creates RTP transports and codec engines according to profile settings.
public enum MediaBootstrap {
    /// Returns a factory for real UDP RTP transport, or nil for loopback (in-process) mode.
    public static func rtpTransportFactory(profile: OperatorProfile) -> (@Sendable () -> any RTPTransport)? {
        switch profile.media.rtpTransport {
        case .loopback:
            return nil
        case .udp:
            return { UDPRTPTransport() }
        }
    }

    /// Picks the best available codec engine for the given audio codec.
    public static func codecEngine(for codec: AudioCodec, profile: OperatorProfile) -> any AudioCodecEngine {
        if codec == .evs {
            return LabEVSCodecEngine()
        }
        if profile.media.useFFmpegCodec, FFmpegAMRCodecEngine.isAvailable {
            return FFmpegAMRCodecEngine(codec: codec)
        }
        return LabAMRCodecEngine(codec: codec)
    }

    /// Returns a factory that creates loopback RTP transports sharing one in-memory bridge.
    public static func sharedLoopbackFactory(bridge: LoopbackRTPBridge) -> @Sendable () -> any RTPTransport {
        { LoopbackRTPTransport(bridge: bridge, isLeftSide: true) }
    }
}
