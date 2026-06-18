import Foundation

// MARK: - File Overview
// Defines the audio codec interface and a lab AMR (Adaptive Multi-Rate) engine.
// Codec engines convert between raw PCM (Pulse-Code Modulation) microphone samples
// and compressed RTP (Real-time Transport Protocol) payloads.

/// Contract for encoding PCM audio to RTP payloads and decoding received payloads.
public protocol AudioCodecEngine: Sendable {
    /// The audio codec this engine implements.
    var codec: AudioCodec { get }
    /// Number of PCM samples per encoded frame.
    var samplesPerFrame: Int { get }
    /// Compresses one frame of PCM audio into an RTP payload.
    func encodePCM(_ pcm: Data) -> Data
    /// Decompresses an RTP payload back into PCM audio.
    func decodeRTPPayload(_ payload: Data) -> Data
}

/// Lab AMR-WB engine: octet-aligned RTP payload framing without licensed compression.
public struct LabAMRCodecEngine: AudioCodecEngine {
    public let codec: AudioCodec
    public let samplesPerFrame: Int

    /// Creates a lab AMR engine for the given codec variant.
    public init(codec: AudioCodec) {
        self.codec = codec
        self.samplesPerFrame = codec == .amrWB ? 320 : 160
    }

    /// Wraps PCM in a minimal octet-aligned AMR RTP payload (0xF0 header byte).
    public func encodePCM(_ pcm: Data) -> Data {
        var payload = Data([0xF0])
        let frameSize = min(pcm.count, codec == .amrWB ? 40 : 20)
        payload.append(pcm.prefix(frameSize))
        if payload.count < 2 {
            payload.append(contentsOf: [0x00, 0x01, 0x02, 0x03])
        }
        return payload
    }

    /// Strips the AMR header nibble and returns PCM bytes from an RTP payload.
    public func decodeRTPPayload(_ payload: Data) -> Data {
        guard !payload.isEmpty else { return Data() }
        if payload[0] & 0xF0 == 0xF0 {
            return payload.dropFirst()
        }
        return payload
    }
}
