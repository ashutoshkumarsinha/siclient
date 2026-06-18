import Foundation

public struct DTMFEvent: Sendable, Equatable {
    public var digit: UInt8
    public var volume: UInt8
    public var duration: UInt16
    public var end: Bool

    public init(digit: UInt8, volume: UInt8 = 10, duration: UInt16 = 160, end: Bool = false) {
        self.digit = digit
        self.volume = volume
        self.duration = duration
        self.end = end
    }
}

public enum DTMFEncoder {
    public static func rtpPayload(for event: DTMFEvent) -> Data {
        var data = Data(capacity: 4)
        data.append(event.digit & 0x7F)
        let volumeByte = (event.end ? 0x80 : 0x00) | (event.volume & 0x3F)
        data.append(volumeByte)
        data.append(UInt8((event.duration >> 8) & 0xFF))
        data.append(UInt8(event.duration & 0xFF))
        return data
    }

    public static func digitCharacter(_ digit: Character) -> UInt8? {
        switch digit {
        case "0"..."9": return UInt8(digit.asciiValue! - Character("0").asciiValue!)
        case "*": return 10
        case "#": return 11
        default: return nil
        }
    }
}
