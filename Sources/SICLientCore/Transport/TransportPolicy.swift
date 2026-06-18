import Foundation

public enum TransportPolicy: Sendable {
    public static let defaultMTUBytes = 1300

    public static func exceedsMTU(_ byteCount: Int, limit: Int = defaultMTUBytes) -> Bool {
        byteCount > limit
    }

    public static func fallbackProtocol(
        for preference: [TransportProtocol],
        current: TransportProtocol
    ) -> TransportProtocol? {
        guard current == .udp else { return nil }
        if preference.contains(.tcp) { return .tcp }
        if preference.contains(.tls) { return .tls }
        return nil
    }

    public static func shouldUseTCPFallback(
        payloadSize: Int,
        mtuLimit: Int,
        preference: [TransportProtocol]
    ) -> Bool {
        exceedsMTU(payloadSize, limit: mtuLimit) && fallbackProtocol(for: preference, current: .udp) != nil
    }
}
