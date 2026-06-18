import Foundation

// MARK: - File Overview
// Describes where and how to send/receive media for a call leg, extracted from SDP
// (Session Description Protocol). Also defines media direction (send, receive, or both).

/// Network address and codec details needed to start an RTP media stream.
public struct MediaEndpoint: Sendable, Equatable {
    public var address: String
    public var port: Int
    public var payloadType: UInt8
    public var codec: AudioCodec
    public var clockRate: Int

    /// Creates a remote media endpoint with IP, port, and codec parameters.
    public init(address: String, port: Int, payloadType: UInt8, codec: AudioCodec, clockRate: Int) {
        self.address = address
        self.port = port
        self.payloadType = payloadType
        self.codec = codec
        self.clockRate = clockRate
    }
}

/// Whether a media session sends audio, receives it, both, or is paused.
public enum MediaDirection: String, Sendable, Equatable {
    /// Both send and receive audio.
    case sendrecv
    /// Only sends audio to the remote party.
    case sendonly
    /// Only receives audio from the remote party.
    case recvonly
    /// Media is paused in both directions.
    case inactive
}

/// Extracts connection details and direction from parsed SDP sessions.
public enum SDPMediaParser {
    /// Builds an audio `MediaEndpoint` by matching preferred codecs against the SDP offer.
    public static func audioEndpoint(from session: SDPSessionDescription, preferred: [AudioCodec]) -> MediaEndpoint? {
        guard let audio = session.media.first(where: { $0.mediaType == "audio" }) else { return nil }
        let offered = SDPParser.offeredAudioCodecs(session)
        let selected = preferred.first(where: { offered.contains($0) })
            ?? offered.first(where: { $0 != .telephoneEvent })
            ?? .amrWB

        // Payload type may differ from our defaults; read it from the rtpmap line.
        var payloadType = UInt8(selected.payloadType)
        for attribute in audio.attributes where attribute.hasPrefix("a=rtpmap:") {
            let parts = attribute.dropFirst(9).split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[1].split(separator: "/").first.map(String.init) ?? ""
            if name.uppercased() == selected.rawValue.uppercased(), let pt = UInt8(parts[0]) {
                payloadType = pt
                break
            }
        }

        return MediaEndpoint(
            address: session.connectionAddress,
            port: audio.port,
            payloadType: payloadType,
            codec: selected,
            clockRate: selected.clockRate
        )
    }

    /// Reads the `a=sendrecv` (or similar) direction attribute from SDP.
    public static func mediaDirection(from session: SDPSessionDescription) -> MediaDirection {
        let attrs = session.media.flatMap(\.attributes) + session.sessionAttributes
        for attribute in attrs {
            let raw = attribute.hasPrefix("a=") ? String(attribute.dropFirst(2)) : attribute
            if let direction = MediaDirection(rawValue: raw) { return direction }
        }
        return .sendrecv
    }

    /// Builds a video `VideoMediaEndpoint` from an SDP session, if video is present.
    public static func videoEndpoint(from session: SDPSessionDescription, preferred: [VideoCodec]) -> VideoMediaEndpoint? {
        guard let video = session.media.first(where: { $0.mediaType == "video" }) else { return nil }
        let selected = preferred.first ?? .h264
        var payloadType = UInt8(selected.payloadType)
        for attribute in video.attributes where attribute.hasPrefix("a=rtpmap:") {
            let parts = attribute.dropFirst(9).split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[1].split(separator: "/").first.map(String.init) ?? ""
            if name.uppercased() == selected.rawValue.uppercased(), let pt = UInt8(parts[0]) {
                payloadType = pt
                break
            }
        }
        return VideoMediaEndpoint(
            address: session.connectionAddress,
            port: video.port,
            payloadType: payloadType,
            codec: selected
        )
    }
}
