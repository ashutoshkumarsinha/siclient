import Foundation

// MARK: - File Overview
// SDP (Session Description Protocol) describes what media a VoLTE call will use:
// codecs, IP addresses, ports, and whether audio is send-only, receive-only, or both.
// This file defines data types for SDP, builds offer/answer bodies for calls, and parses
// SDP text received from the network into structured objects.

/// One media stream block inside an SDP document (e.g. an audio line with port and codecs).
public struct SDPMediaDescription: Sendable, Equatable {
    public var mediaType: String
    public var port: Int
    public var transport: String
    public var formats: [String]
    public var attributes: [String]

    /// Creates a media description, defaulting transport to RTP/AVP (RTP over UDP with profile).
    public init(
        mediaType: String,
        port: Int,
        transport: String = "RTP/AVP",
        formats: [String],
        attributes: [String] = []
    ) {
        self.mediaType = mediaType
        self.port = port
        self.transport = transport
        self.formats = formats
        self.attributes = attributes
    }

    /// All attribute lines attached to this media block.
    public var allAttributes: [String] { attributes }
}

/// A complete SDP session: origin info, connection address, and one or more media blocks.
public struct SDPSessionDescription: Sendable, Equatable {
    public var originUsername: String
    public var sessionID: String
    public var sessionVersion: String
    public var originAddress: String
    public var sessionName: String
    public var connectionAddress: String
    public var timing: String
    public var media: [SDPMediaDescription]
    public var sessionAttributes: [String]

    /// Creates an SDP session description with sensible defaults for lab use.
    public init(
        originUsername: String = "-",
        sessionID: String = "0",
        sessionVersion: String = "0",
        originAddress: String,
        sessionName: String = "-",
        connectionAddress: String,
        timing: String = "t=0 0",
        media: [SDPMediaDescription] = [],
        sessionAttributes: [String] = []
    ) {
        self.originUsername = originUsername
        self.sessionID = sessionID
        self.sessionVersion = sessionVersion
        self.originAddress = originAddress
        self.sessionName = sessionName
        self.connectionAddress = connectionAddress
        self.timing = timing
        self.media = media
        self.sessionAttributes = sessionAttributes
    }

    /// Reads QoS precondition status from SDP attribute lines.
    public var preconditionState: PreconditionState {
        let attrs = media.flatMap(\.attributes) + sessionAttributes
        return PreconditionState.parse(from: attrs)
    }

    /// Converts this session into the plain-text SDP body sent in SIP messages.
    public func serialize() -> String {
        var lines = [
            "v=0",
            "o=\(originUsername) \(sessionID) \(sessionVersion) IN IP4 \(originAddress)",
            "s=\(sessionName)",
            "c=IN IP4 \(connectionAddress)",
            timing,
        ]
        lines.append(contentsOf: sessionAttributes)
        for m in media {
            lines.append("m=\(m.mediaType) \(m.port) \(m.transport) \(m.formats.joined(separator: " "))")
            lines.append(contentsOf: m.attributes)
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

/// Factory methods that build common VoLTE SDP offer and answer bodies.
public enum SDPSessionBuilder {
    /// Builds SDP for a single negotiated audio codec after the call is established.
    public static func voLTEMediaSDP(
        profile: OperatorProfile,
        localIP: String,
        audioPort: Int,
        codec: AudioCodec,
        direction: MediaDirection,
        preconditionState: PreconditionState = PreconditionState(local: .sendrecv, remote: .sendrecv)
    ) -> SDPSessionDescription {
        var attributes: [String] = [
            SDPCodecMapper.rtpmapLine(codec: codec),
        ]
        if let fmtp = SDPCodecMapper.fmtpLine(codec: codec) {
            attributes.append(fmtp)
        }
        if profile.preconditions.enabled {
            attributes.append(contentsOf: preconditionState.currAttributes())
        }
        attributes.append("a=\(direction.rawValue)")
        let audio = SDPMediaDescription(
            mediaType: "audio",
            port: audioPort,
            formats: [String(codec.payloadType)],
            attributes: attributes
        )
        return SDPSessionDescription(originAddress: localIP, connectionAddress: localIP, media: [audio])
    }

    /// Builds an SDP offer listing all codecs the client is willing to use.
    public static func voLTEOffer(
        profile: OperatorProfile,
        localIP: String,
        audioPort: Int,
        preconditionState: PreconditionState = PreconditionState(),
        includeVideo: Bool = false
    ) -> SDPSessionDescription {
        let codecs = AudioCodec.fromProfile(profile.codecs.audio)
        let formats = codecs.map { String($0.payloadType) }
        var attributes: [String] = []
        for codec in codecs {
            attributes.append(SDPCodecMapper.rtpmapLine(codec: codec))
            if let fmtp = SDPCodecMapper.fmtpLine(codec: codec) {
                attributes.append(fmtp)
            }
        }
        if profile.preconditions.enabled {
            attributes.append(contentsOf: preconditionState.currAttributes())
            attributes.append(contentsOf: PreconditionState.desiredAttributes(enabled: true))
        }
        attributes.append("a=sendrecv")

        let audio = SDPMediaDescription(
            mediaType: "audio",
            port: audioPort,
            formats: formats,
            attributes: attributes
        )

        var mediaBlocks = [audio]
        if includeVideo, let video = VideoCodec.fromProfile(profile.codecs.video).first {
            // Video typically uses the next even port after audio.
            mediaBlocks.append(
                SDPMediaDescription(
                    mediaType: "video",
                    port: audioPort + 2,
                    formats: [String(video.payloadType)],
                    attributes: [
                        SDPVideoMapper.rtpmapLine(codec: video),
                        SDPVideoMapper.fmtpLine(codec: video),
                        "a=sendrecv",
                    ]
                )
            )
        }

        return SDPSessionDescription(
            originAddress: localIP,
            connectionAddress: localIP,
            media: mediaBlocks
        )
    }

    /// Builds an SDP answer picking one codec from what the remote side offered.
    public static func voLTEAnswer(
        profile: OperatorProfile,
        localIP: String,
        audioPort: Int,
        offeredCodecs: [AudioCodec],
        preconditionState: PreconditionState,
        direction: MediaDirection = .sendrecv
    ) -> SDPSessionDescription {
        let selected = selectCodec(preferred: AudioCodec.fromProfile(profile.codecs.audio), offered: offeredCodecs)
        var attributes: [String] = []
        attributes.append(SDPCodecMapper.rtpmapLine(codec: selected))
        if let fmtp = SDPCodecMapper.fmtpLine(codec: selected) {
            attributes.append(fmtp)
        }
        if profile.preconditions.enabled {
            attributes.append(contentsOf: preconditionState.currAttributes())
            attributes.append(contentsOf: PreconditionState.desiredAttributes(enabled: true))
        }
        attributes.append("a=\(direction.rawValue)")

        return SDPSessionDescription(
            originAddress: localIP,
            connectionAddress: localIP,
            media: [
                SDPMediaDescription(
                    mediaType: "audio",
                    port: audioPort,
                    formats: [String(selected.payloadType)],
                    attributes: attributes
                ),
            ]
        )
    }

    /// Picks the first preferred codec that also appears in the remote offer.
    private static func selectCodec(preferred: [AudioCodec], offered: [AudioCodec]) -> AudioCodec {
        for codec in preferred where offered.contains(codec) {
            return codec
        }
        // Fall back to any offered codec except DTMF tones, or AMR-WB as last resort.
        return offered.first(where: { $0 != .telephoneEvent }) ?? .amrWB
    }
}

/// Parses raw SDP text into structured session descriptions.
public enum SDPParser {
    /// Reads an SDP string line-by-line into an `SDPSessionDescription`.
    public static func parse(_ text: String) -> SDPSessionDescription {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var originUsername = "-"
        var sessionID = "0"
        var sessionVersion = "0"
        var originAddress = "0.0.0.0"
        var sessionName = "-"
        var connectionAddress = "0.0.0.0"
        var timing = "t=0 0"
        var sessionAttributes: [String] = []
        var media: [SDPMediaDescription] = []
        var currentMedia: SDPMediaDescription?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let type = line[..<separator]
            let value = String(line[line.index(after: separator)...])

            switch type {
            case "o":
                let parts = value.split(separator: " ").map(String.init)
                if parts.count >= 6 {
                    originUsername = parts[0]
                    sessionID = parts[1]
                    sessionVersion = parts[2]
                    originAddress = parts[5]
                }
            case "s":
                sessionName = value
            case "c":
                let parts = value.split(separator: " ")
                if let addr = parts.last { connectionAddress = String(addr) }
            case "t":
                timing = "t=\(value)"
            case "m":
                // A new m= line starts a new media block; save the previous one first.
                if let currentMedia { media.append(currentMedia) }
                let parts = value.split(separator: " ").map(String.init)
                guard parts.count >= 4 else { continue }
                currentMedia = SDPMediaDescription(
                    mediaType: parts[0],
                    port: Int(parts[1]) ?? 0,
                    transport: parts[2],
                    formats: Array(parts.dropFirst(3)),
                    attributes: []
                )
            case "a":
                // Attribute lines belong to the current media block, or to the session if none is open.
                if var mediaBlock = currentMedia {
                    mediaBlock.attributes.append("a=\(value)")
                    currentMedia = mediaBlock
                } else {
                    sessionAttributes.append("a=\(value)")
                }
            default:
                break
            }
        }
        if let currentMedia { media.append(currentMedia) }

        return SDPSessionDescription(
            originUsername: originUsername,
            sessionID: sessionID,
            sessionVersion: sessionVersion,
            originAddress: originAddress,
            sessionName: sessionName,
            connectionAddress: connectionAddress,
            timing: timing,
            media: media,
            sessionAttributes: sessionAttributes
        )
    }

    /// Extracts the list of audio codecs advertised in an SDP session.
    public static func offeredAudioCodecs(_ session: SDPSessionDescription) -> [AudioCodec] {
        guard let audio = session.media.first(where: { $0.mediaType == "audio" }) else { return [] }
        var codecs: [AudioCodec] = []
        for attribute in audio.attributes {
            guard attribute.hasPrefix("a=rtpmap:") else { continue }
            let payload = attribute.split(separator: " ").map(String.init)
            guard payload.count >= 2 else { continue }
            let codecName = payload[1].split(separator: "/").first.map(String.init) ?? ""
            switch codecName.uppercased() {
            case "EVS": codecs.append(.evs)
            case "AMR-WB": codecs.append(.amrWB)
            case "AMR": codecs.append(.amr)
            case "TELEPHONE-EVENT": codecs.append(.telephoneEvent)
            default: break
            }
        }
        return codecs
    }
}
