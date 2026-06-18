import Foundation

public enum MediaBootstrap {
    public static func rtpTransportFactory(profile: OperatorProfile) -> (@Sendable () -> any RTPTransport)? {
        switch profile.media.rtpTransport {
        case .loopback:
            return nil
        case .udp:
            return { UDPRTPTransport() }
        }
    }

    public static func codecEngine(for codec: AudioCodec, profile: OperatorProfile) -> any AudioCodecEngine {
        if codec == .evs {
            return LabEVSCodecEngine()
        }
        if profile.media.useFFmpegCodec, FFmpegAMRCodecEngine.isAvailable {
            return FFmpegAMRCodecEngine(codec: codec)
        }
        return LabAMRCodecEngine(codec: codec)
    }

    public static func sharedLoopbackFactory(bridge: LoopbackRTPBridge) -> @Sendable () -> any RTPTransport {
        { LoopbackRTPTransport(bridge: bridge, isLeftSide: true) }
    }
}
