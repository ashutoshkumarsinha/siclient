import Foundation

// MARK: - File Overview
// Defines the audio codecs used in VoLTE calls and maps them to SDP attribute lines.
// SDP (Session Description Protocol) uses rtpmap/fmtp lines to tell the remote party
// which codec numbers and settings to use.

/// Supported audio codecs for VoLTE media sessions.
public enum AudioCodec: String, Sendable, CaseIterable {
    case evs = "EVS"
    case amrWB = "AMR-WB"
    case amr = "AMR"
    case telephoneEvent = "telephone-event"

    /// Sample rate in Hz used by RTP (Real-time Transport Protocol) timestamps for this codec.
    public var clockRate: Int {
        switch self {
        case .evs, .amrWB: return 16000
        case .amr, .telephoneEvent: return 8000
        }
    }

    /// RTP payload type number assigned to this codec in SDP.
    public var payloadType: Int {
        switch self {
        case .evs: return 110
        case .amrWB: return 103
        case .amr: return 102
        case .telephoneEvent: return 101
        }
    }

    /// Converts profile codec name strings into typed codec values, always including DTMF support.
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

/// Builds SDP rtpmap and fmtp lines for audio codecs.
public enum SDPCodecMapper {
    /// Returns the `a=rtpmap:` line linking payload type to codec name and clock rate.
    public static func rtpmapLine(codec: AudioCodec) -> String {
        "a=rtpmap:\(codec.payloadType) \(codec.rawValue)/\(codec.clockRate)"
    }

    /// Returns the optional `a=fmtp:` line with codec-specific parameters, if any.
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
