import Foundation

// MARK: - File overview
//
// Rules for when SIP (Session Initiation Protocol) messages should switch from UDP
// to a reliable transport (TCP or TLS). Large REGISTER bodies can exceed the MTU
// (Maximum Transmission Unit), so operators often allow TCP/TLS fallback.

/// Helpers for MTU limits and UDP-to-TCP/TLS fallback decisions.
public enum TransportPolicy: Sendable {
    /// Default safe MTU size (bytes) for SIP over UDP on mobile networks.
    public static let defaultMTUBytes = 1300

    /// Returns true when a SIP message is too large to send reliably over UDP.
    public static func exceedsMTU(_ byteCount: Int, limit: Int = defaultMTUBytes) -> Bool {
        byteCount > limit
    }

    /// Returns the next preferred transport after UDP (TCP preferred over TLS).
    public static func fallbackProtocol(
        for preference: [TransportProtocol],
        current: TransportProtocol
    ) -> TransportProtocol? {
        guard current == .udp else { return nil }
        if preference.contains(.tcp) { return .tcp }
        if preference.contains(.tls) { return .tls }
        return nil
    }

    /// True when the payload is over the MTU and a TCP/TLS fallback is configured.
    public static func shouldUseTCPFallback(
        payloadSize: Int,
        mtuLimit: Int,
        preference: [TransportProtocol]
    ) -> Bool {
        exceedsMTU(payloadSize, limit: mtuLimit) && fallbackProtocol(for: preference, current: .udp) != nil
    }
}
