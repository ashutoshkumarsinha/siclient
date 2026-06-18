import Foundation

public struct MediaEndpoint: Sendable, Equatable {
    public var address: String
    public var port: Int
    public var payloadType: UInt8
    public var codec: AudioCodec
    public var clockRate: Int

    public init(address: String, port: Int, payloadType: UInt8, codec: AudioCodec, clockRate: Int) {
        self.address = address
        self.port = port
        self.payloadType = payloadType
        self.codec = codec
        self.clockRate = clockRate
    }
}

public enum MediaDirection: String, Sendable, Equatable {
    case sendrecv
    case sendonly
    case recvonly
    case inactive
}

public enum SDPMediaParser {
    public static func audioEndpoint(from session: SDPSessionDescription, preferred: [AudioCodec]) -> MediaEndpoint? {
        guard let audio = session.media.first(where: { $0.mediaType == "audio" }) else { return nil }
        let offered = SDPParser.offeredAudioCodecs(session)
        let selected = preferred.first(where: { offered.contains($0) })
            ?? offered.first(where: { $0 != .telephoneEvent })
            ?? .amrWB

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

    public static func mediaDirection(from session: SDPSessionDescription) -> MediaDirection {
        let attrs = session.media.flatMap(\.attributes) + session.sessionAttributes
        for attribute in attrs {
            let raw = attribute.hasPrefix("a=") ? String(attribute.dropFirst(2)) : attribute
            if let direction = MediaDirection(rawValue: raw) { return direction }
        }
        return .sendrecv
    }

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
