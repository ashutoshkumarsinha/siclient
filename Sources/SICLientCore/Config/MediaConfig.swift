import Foundation

// MARK: - File overview
//
// Media-layer settings from the operator profile: RTP (Real-time Transport Protocol)
// transport mode, local port, and flags for audio I/O, video, and FFmpeg codecs.

/// How RTP media packets are carried (loopback for tests, UDP for real networks).
public enum RTPTransportMode: String, Codable, Sendable {
    case loopback
    case udp
}

/// Audio/video media configuration for VoLTE (Voice over LTE) sessions.
public struct MediaConfig: Codable, Sendable, Equatable {
    public var rtpTransport: RTPTransportMode
    /// Local UDP port for incoming RTP audio.
    public var localRTPPort: Int
    /// Whether to capture/play real microphone/speaker audio.
    public var enableAudioIO: Bool
    /// Whether video media is enabled.
    public var enableVideo: Bool
    /// Whether to use FFmpeg for codec encode/decode.
    public var useFFmpegCodec: Bool

    enum CodingKeys: String, CodingKey {
        case rtpTransport = "rtp_transport"
        case localRTPPort = "local_rtp_port"
        case enableAudioIO = "enable_audio_io"
        case enableVideo = "enable_video"
        case useFFmpegCodec = "use_ffmpeg_codec"
    }

    /// Creates media settings with UDP RTP on port 40000 and I/O disabled.
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
