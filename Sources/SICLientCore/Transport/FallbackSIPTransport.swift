import Foundation

// MARK: - File overview
//
// A SIP transport that tries UDP first and falls back to TCP/TLS when messages are
// too large (over MTU) or when UDP send fails. IMS (IP Multimedia Subsystem) clients
// commonly need this for big REGISTER requests with many security headers.

/// Wraps a primary (usually UDP) and fallback (TCP/TLS) SIP transport.
public final class FallbackSIPTransport: SIPTransport, @unchecked Sendable {
    public let isReliable = false
    private let primary: any SIPTransport
    private let fallback: any SIPTransport
    private let mtuLimit: Int
    private var preferFallback = false

    var lastSendUsedFallback = false

    /// Pairs a primary transport with a fallback and an MTU byte limit for oversized messages.
    public init(primary: any SIPTransport, fallback: any SIPTransport, mtuLimit: Int = TransportPolicy.defaultMTUBytes) {
        self.primary = primary
        self.fallback = fallback
        self.mtuLimit = mtuLimit
    }

    /// Connects only the primary transport; fallback connects on first use.
    public func connect() async throws {
        try await primary.connect()
    }

    /// Sends via primary unless MTU is exceeded or a prior send failed on UDP.
    public func send(_ data: Data) async throws {
        let needsFallback = preferFallback || TransportPolicy.exceedsMTU(data.count, limit: mtuLimit)
        if needsFallback {
            try await ensureFallbackConnected()
            lastSendUsedFallback = true
            try await fallback.send(data)
            return
        }

        do {
            lastSendUsedFallback = false
            try await primary.send(data)
        } catch {
            // UDP failed — stick with fallback for subsequent sends
            preferFallback = true
            try await ensureFallbackConnected()
            lastSendUsedFallback = true
            try await fallback.send(data)
        }
    }

    /// Receives from fallback if active, otherwise tries primary then fallback.
    public func receive(timeout: Duration) async throws -> Data? {
        if preferFallback {
            return try await fallback.receive(timeout: timeout)
        }
        if let data = try await primary.receive(timeout: timeout) {
            return data
        }
        return try await fallback.receive(timeout: timeout)
    }

    /// Closes both transports and resets fallback preference.
    public func close() async {
        await primary.close()
        await fallback.close()
        preferFallback = false
    }

    /// Lazily connects the fallback transport and marks it as preferred.
    private func ensureFallbackConnected() async throws {
        try await fallback.connect()
        preferFallback = true
    }
}
