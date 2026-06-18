import Foundation

public protocol AudioCodecEngine: Sendable {
    var codec: AudioCodec { get }
    var samplesPerFrame: Int { get }
    func encodePCM(_ pcm: Data) -> Data
    func decodeRTPPayload(_ payload: Data) -> Data
}

/// Lab AMR-WB engine: octet-aligned RTP payload framing without licensed compression.
public struct LabAMRCodecEngine: AudioCodecEngine {
    public let codec: AudioCodec
    public let samplesPerFrame: Int

    public init(codec: AudioCodec) {
        self.codec = codec
        self.samplesPerFrame = codec == .amrWB ? 320 : 160
    }

    public func encodePCM(_ pcm: Data) -> Data {
        var payload = Data([0xF0])
        let frameSize = min(pcm.count, codec == .amrWB ? 40 : 20)
        payload.append(pcm.prefix(frameSize))
        if payload.count < 2 {
            payload.append(contentsOf: [0x00, 0x01, 0x02, 0x03])
        }
        return payload
    }

    public func decodeRTPPayload(_ payload: Data) -> Data {
        guard !payload.isEmpty else { return Data() }
        if payload[0] & 0xF0 == 0xF0 {
            return payload.dropFirst()
        }
        return payload
    }
}
