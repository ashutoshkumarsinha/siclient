import Foundation

public enum AudioCodec: String, Sendable, CaseIterable {
    case evs = "EVS"
    case amrWB = "AMR-WB"
    case amr = "AMR"
    case telephoneEvent = "telephone-event"

    public var clockRate: Int {
        switch self {
        case .evs, .amrWB: return 16000
        case .amr, .telephoneEvent: return 8000
        }
    }

    public var payloadType: Int {
        switch self {
        case .evs: return 110
        case .amrWB: return 103
        case .amr: return 102
        case .telephoneEvent: return 101
        }
    }

    public static func fromProfile(_ names: [String]) -> [AudioCodec] {
        var codecs: [AudioCodec] = []
        for name in names {
            switch name.uppercased() {
            case "EVS": codecs.append(.evs)
            case "AMR-WB": codecs.append(.amrWB)
            case "AMR": codecs.append(.amr)
            default: break
            }
        }
        if !codecs.contains(.telephoneEvent) {
            codecs.append(.telephoneEvent)
        }
        return codecs
    }
}

public enum SDPCodecMapper {
    public static func rtpmapLine(codec: AudioCodec) -> String {
        "a=rtpmap:\(codec.payloadType) \(codec.rawValue)/\(codec.clockRate)"
    }

    public static func fmtpLine(codec: AudioCodec) -> String? {
        switch codec {
        case .evs:
            return "a=fmtp:\(codec.payloadType) br=13.2-128; bw=nb-swb; ch-aw-recv=2"
        case .amrWB, .amr:
            return "a=fmtp:\(codec.payloadType) mode-set=0,1,2,3,4,5,6,7;mode-change-capability=2;max-red=0"
        case .telephoneEvent:
            return "a=fmtp:\(codec.payloadType) 0-15"
        }
    }
}
