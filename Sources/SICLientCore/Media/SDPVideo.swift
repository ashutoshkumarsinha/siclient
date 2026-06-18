import Foundation

// MARK: - File Overview
// Defines video codecs (H.264, H.265) and builds SDP (Session Description Protocol)
// attribute lines for video streams in VoLTE calls.

/// Supported video codecs for VoLTE video calls.
public enum VideoCodec: String, Sendable, CaseIterable {
    case h264 = "H264"
    case h265 = "H265"

    /// RTP payload type number assigned to this video codec in SDP.
    public var payloadType: Int {
        switch self {
        case .h264: return 96
        case .h265: return 97
        }
    }

    /// Video RTP (Real-time Transport Protocol) clock rate is always 90 kHz per RFC 3551.
    public var clockRate: Int { 90_000 }

    /// Converts profile codec name strings into typed video codec values.
    public static func fromProfile(_ names: [String]) -> [VideoCodec] {
        names.compactMap { name in
            switch name.uppercased() {
            case "H264": return .h264
            case "H265": return .h265
            default: return nil
            }
        }
    }
}

/// Builds SDP rtpmap and fmtp lines for video codecs.
public enum SDPVideoMapper {
    /// Returns the `a=rtpmap:` line linking payload type to video codec name and clock rate.
    public static func rtpmapLine(codec: VideoCodec) -> String {
        "a=rtpmap:\(codec.payloadType) \(codec.rawValue)/\(codec.clockRate)"
    }

    /// Returns the `a=fmtp:` line with codec-specific profile and level parameters.
    public static func fmtpLine(codec: VideoCodec) -> String {
        switch codec {
        case .h264:
            return "a=fmtp:\(codec.payloadType) profile-level-id=42e01f;packetization-mode=1"
        case .h265:
            return "a=fmtp:\(codec.payloadType) profile-id=1;level-id=93;tier-flag=0"
        }
    }
}
