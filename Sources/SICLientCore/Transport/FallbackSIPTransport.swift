import Foundation

public final class FallbackSIPTransport: SIPTransport, @unchecked Sendable {
    public let isReliable = false
    private let primary: any SIPTransport
    private let fallback: any SIPTransport
    private let mtuLimit: Int
    private var preferFallback = false

    var lastSendUsedFallback = false

    public init(primary: any SIPTransport, fallback: any SIPTransport, mtuLimit: Int = TransportPolicy.defaultMTUBytes) {
        self.primary = primary
        self.fallback = fallback
        self.mtuLimit = mtuLimit
    }

    public func connect() async throws {
        try await primary.connect()
    }

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
            preferFallback = true
            try await ensureFallbackConnected()
            lastSendUsedFallback = true
            try await fallback.send(data)
        }
    }

    public func receive(timeout: Duration) async throws -> Data? {
        if preferFallback {
            return try await fallback.receive(timeout: timeout)
        }
        if let data = try await primary.receive(timeout: timeout) {
            return data
        }
        return try await fallback.receive(timeout: timeout)
    }

    public func close() async {
        await primary.close()
        await fallback.close()
        preferFallback = false
    }

    private func ensureFallbackConnected() async throws {
        try await fallback.connect()
        preferFallback = true
    }
}
