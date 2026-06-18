import Foundation

// MARK: - File Overview
// Encodes DTMF (Dual-Tone Multi-Frequency) keypad tones into RTP (Real-time Transport
// Protocol) telephone-event payloads. Used when the user presses digits during a call.

/// One DTMF tone event: which digit, how loud, how long, and whether it has ended.
public struct DTMFEvent: Sendable, Equatable {
    public var digit: UInt8
    public var volume: UInt8
    public var duration: UInt16
    public var end: Bool

    /// Creates a DTMF event with default volume and duration suitable for RTP.
    public init(digit: UInt8, volume: UInt8 = 10, duration: UInt16 = 160, end: Bool = false) {
        self.digit = digit
        self.volume = volume
        self.duration = duration
        self.end = end
    }
}

/// Builds RTP payloads for RFC 4733 telephone-event (DTMF) packets.
public enum DTMFEncoder {
    /// Serializes a DTMF event into a 4-byte RTP telephone-event payload.
    public static func rtpPayload(for event: DTMFEvent) -> Data {
        var data = Data(capacity: 4)
        data.append(event.digit & 0x7F)
        // High bit of byte 2 marks the end of the tone.
        let volumeByte = (event.end ? 0x80 : 0x00) | (event.volume & 0x3F)
        data.append(volumeByte)
        data.append(UInt8((event.duration >> 8) & 0xFF))
        data.append(UInt8(event.duration & 0xFF))
        return data
    }

    /// Maps a keypad character (0–9, *, #) to its DTMF event digit code.
    public static func digitCharacter(_ digit: Character) -> UInt8? {
        switch digit {
        case "0"..."9": return UInt8(digit.asciiValue! - Character("0").asciiValue!)
        case "*": return 10
        case "#": return 11
        default: return nil
        }
    }
}
