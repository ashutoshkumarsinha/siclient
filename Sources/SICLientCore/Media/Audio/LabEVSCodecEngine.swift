import Foundation

// MARK: - File Overview
// Lab stub for the EVS (Enhanced Voice Services) audio codec. Provides encode/decode
// without a licensed codec library — useful for testing RTP (Real-time Transport
// Protocol) flow in development.

/// Simplified EVS codec engine for lab and test environments.
public struct LabEVSCodecEngine: AudioCodecEngine {
    public let codec: AudioCodec = .evs
    public let samplesPerFrame = 320

    /// Creates a lab EVS codec engine.
    public init() {}

    /// Wraps raw PCM bytes in a minimal EVS-style RTP payload header.
    public func encodePCM(_ pcm: Data) -> Data {
        var payload = Data([0x00])
        payload.append(pcm.prefix(48))
        if payload.count < 4 {
            payload.append(contentsOf: [0x01, 0x02, 0x03])
        }
        return payload
    }

    /// Strips the lab header and returns PCM bytes from an RTP payload.
    public func decodeRTPPayload(_ payload: Data) -> Data {
        guard !payload.isEmpty else { return Data() }
        if payload[0] == 0x00, payload.count > 1 {
            return payload.dropFirst()
        }
        return payload
    }
}
