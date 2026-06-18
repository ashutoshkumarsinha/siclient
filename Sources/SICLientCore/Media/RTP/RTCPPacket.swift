import Foundation

public struct RTCPReceiverReport: Sendable, Equatable {
    public var ssrc: UInt32
    public var fractionLost: UInt8
    public var cumulativeLost: Int32
    public var highestSequence: UInt32
    public var jitter: UInt32
}

public struct RTCPSenderReport: Sendable, Equatable {
    public var ssrc: UInt32
    public var ntpSeconds: UInt32
    public var ntpFraction: UInt32
    public var rtpTimestamp: UInt32
    public var packetCount: UInt32
    public var octetCount: UInt32
    public var reports: [RTCPReceiverReport]
}

public enum RTCPPacket {
    public static func buildSenderReport(
        ssrc: UInt32,
        rtpTimestamp: UInt32,
        packetCount: UInt32,
        octetCount: UInt32,
        reports: [RTCPReceiverReport] = []
    ) -> Data {
        let reportCount = UInt8(min(reports.count, 31))
        var data = Data()
        data.append(0x80 | reportCount)
        data.append(200)
        let length = UInt16(6 + reports.count * 6 - 1)
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        appendUInt32(ssrc, to: &data)

        let now = Date().timeIntervalSince1970
        let ntpSeconds = UInt32(now) + 2_208_988_800
        let ntpFraction = UInt32((now.truncatingRemainder(dividingBy: 1)) * 4_294_967_296.0)
        appendUInt32(ntpSeconds, to: &data)
        appendUInt32(ntpFraction, to: &data)
        appendUInt32(rtpTimestamp, to: &data)
        appendUInt32(packetCount, to: &data)
        appendUInt32(octetCount, to: &data)

        for report in reports {
            appendUInt32(report.ssrc, to: &data)
            data.append(report.fractionLost)
            let lost = UInt32(bitPattern: report.cumulativeLost) & 0x00FF_FFFF
            data.append(UInt8((lost >> 16) & 0xFF))
            data.append(UInt8((lost >> 8) & 0xFF))
            data.append(UInt8(lost & 0xFF))
            appendUInt32(report.highestSequence, to: &data)
            appendUInt32(report.jitter, to: &data)
            appendUInt32(0, to: &data)
            appendUInt32(0, to: &data)
        }
        return data
    }

    public static func parseReceiverReport(_ data: Data) -> RTCPReceiverReport? {
        guard data.count >= 8 else { return nil }
        let packetType = data[1]
        guard packetType == 201 else { return nil }
        guard data.count >= 32 else {
            let senderSSRC = readUInt32(data, offset: 4)
            return RTCPReceiverReport(
                ssrc: senderSSRC,
                fractionLost: 0,
                cumulativeLost: 0,
                highestSequence: 0,
                jitter: 0
            )
        }

        let reportedSSRC = readUInt32(data, offset: 8)
        let fraction = data[12]
        let lost = Int32((UInt32(data[13]) << 16) | (UInt32(data[14]) << 8) | UInt32(data[15]))
        let highest = readUInt32(data, offset: 16)
        let jitter = readUInt32(data, offset: 20)
        return RTCPReceiverReport(
            ssrc: reportedSSRC,
            fractionLost: fraction,
            cumulativeLost: lost,
            highestSequence: highest,
            jitter: jitter
        )
    }

    public static func parseSenderReport(_ data: Data) -> RTCPSenderReport? {
        guard data.count >= 28 else { return nil }
        guard data[1] == 200 else { return nil }
        let ssrc = readUInt32(data, offset: 4)
        let ntpSeconds = readUInt32(data, offset: 8)
        let ntpFraction = readUInt32(data, offset: 12)
        let rtpTimestamp = readUInt32(data, offset: 16)
        let packetCount = readUInt32(data, offset: 20)
        let octetCount = readUInt32(data, offset: 24)
        return RTCPSenderReport(
            ssrc: ssrc,
            ntpSeconds: ntpSeconds,
            ntpFraction: ntpFraction,
            rtpTimestamp: rtpTimestamp,
            packetCount: packetCount,
            octetCount: octetCount,
            reports: []
        )
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}
