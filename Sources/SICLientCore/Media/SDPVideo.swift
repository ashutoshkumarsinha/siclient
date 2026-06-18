import Foundation

public enum VideoCodec: String, Sendable, CaseIterable {
    case h264 = "H264"
    case h265 = "H265"

    public var payloadType: Int {
        switch self {
        case .h264: return 96
        case .h265: return 97
        }
    }

    public var clockRate: Int { 90_000 }

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

public enum SDPVideoMapper {
    public static func rtpmapLine(codec: VideoCodec) -> String {
        "a=rtpmap:\(codec.payloadType) \(codec.rawValue)/\(codec.clockRate)"
    }

    public static func fmtpLine(codec: VideoCodec) -> String {
        switch codec {
        case .h264:
            return "a=fmtp:\(codec.payloadType) profile-level-id=42e01f;packetization-mode=1"
        case .h265:
            return "a=fmtp:\(codec.payloadType) profile-id=1;level-id=93;tier-flag=0"
        }
    }
}
