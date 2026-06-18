import Foundation

public struct LabEVSCodecEngine: AudioCodecEngine {
    public let codec: AudioCodec = .evs
    public let samplesPerFrame = 320

    public init() {}

    public func encodePCM(_ pcm: Data) -> Data {
        var payload = Data([0x00])
        payload.append(pcm.prefix(48))
        if payload.count < 4 {
            payload.append(contentsOf: [0x01, 0x02, 0x03])
        }
        return payload
    }

    public func decodeRTPPayload(_ payload: Data) -> Data {
        guard !payload.isEmpty else { return Data() }
        if payload[0] == 0x00, payload.count > 1 {
            return payload.dropFirst()
        }
        return payload
    }
}
