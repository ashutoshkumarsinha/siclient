import Foundation

public enum RTPTransportMode: String, Codable, Sendable {
    case loopback
    case udp
}

public struct MediaConfig: Codable, Sendable, Equatable {
    public var rtpTransport: RTPTransportMode
    public var localRTPPort: Int
    public var enableAudioIO: Bool
    public var enableVideo: Bool
    public var useFFmpegCodec: Bool

    enum CodingKeys: String, CodingKey {
        case rtpTransport = "rtp_transport"
        case localRTPPort = "local_rtp_port"
        case enableAudioIO = "enable_audio_io"
        case enableVideo = "enable_video"
        case useFFmpegCodec = "use_ffmpeg_codec"
    }

    public init(
        rtpTransport: RTPTransportMode = .udp,
        localRTPPort: Int = 40000,
        enableAudioIO: Bool = false,
        enableVideo: Bool = false,
        useFFmpegCodec: Bool = false
    ) {
        self.rtpTransport = rtpTransport
        self.localRTPPort = localRTPPort
        self.enableAudioIO = enableAudioIO
        self.enableVideo = enableVideo
        self.useFFmpegCodec = useFFmpegCodec
    }
}
