import Foundation

public struct RTPPacket: Sendable, Equatable {
    public var version: UInt8
    public var padding: Bool
    public var marker: Bool
    public var payloadType: UInt8
    public var sequenceNumber: UInt16
    public var timestamp: UInt32
    public var ssrc: UInt32
    public var payload: Data

    public init(
        version: UInt8 = 2,
        padding: Bool = false,
        marker: Bool = false,
        payloadType: UInt8,
        sequenceNumber: UInt16,
        timestamp: UInt32,
        ssrc: UInt32,
        payload: Data
    ) {
        self.version = version
        self.padding = padding
        self.marker = marker
        self.payloadType = payloadType
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.ssrc = ssrc
        self.payload = payload
    }

    public func serialize() -> Data {
        var data = Data(capacity: 12 + payload.count)
        let byte0 = (version & 0x03) << 6 | (padding ? 0x20 : 0) | 0
        let byte1 = (marker ? 0x80 : 0) | (payloadType & 0x7F)
        data.append(byte0)
        data.append(byte1)
        data.append(UInt8((sequenceNumber >> 8) & 0xFF))
        data.append(UInt8(sequenceNumber & 0xFF))
        data.append(UInt8((timestamp >> 24) & 0xFF))
        data.append(UInt8((timestamp >> 16) & 0xFF))
        data.append(UInt8((timestamp >> 8) & 0xFF))
        data.append(UInt8(timestamp & 0xFF))
        data.append(UInt8((ssrc >> 24) & 0xFF))
        data.append(UInt8((ssrc >> 16) & 0xFF))
        data.append(UInt8((ssrc >> 8) & 0xFF))
        data.append(UInt8(ssrc & 0xFF))
        data.append(payload)
        return data
    }

    public static func parse(_ data: Data) -> RTPPacket? {
        guard data.count >= 12 else { return nil }
        let byte0 = data[0]
        let version = (byte0 >> 6) & 0x03
        guard version == 2 else { return nil }
        let padding = (byte0 & 0x20) != 0
        let csrcCount = Int(byte0 & 0x0F)
        let headerLength = 12 + csrcCount * 4
        guard data.count >= headerLength else { return nil }

        let byte1 = data[1]
        let marker = (byte1 & 0x80) != 0
        let payloadType = byte1 & 0x7F
        let sequence = UInt16(data[2]) << 8 | UInt16(data[3])
        let timestamp = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        let ssrc = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        var payload = data.subdata(in: headerLength..<data.count)
        if padding, let padCount = payload.last, Int(padCount) <= payload.count {
            payload.removeLast(Int(padCount))
        }
        return RTPPacket(
            version: version,
            padding: padding,
            marker: marker,
            payloadType: payloadType,
            sequenceNumber: sequence,
            timestamp: timestamp,
            ssrc: ssrc,
            payload: payload
        )
    }
}
