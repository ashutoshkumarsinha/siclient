import Foundation

// MARK: - File overview
//
// Defines the interface for requesting dedicated LTE bearers. VoLTE (Voice over LTE)
// needs a bearer with voice QCI (QoS Class Identifier) to get guaranteed bandwidth
// for RTP (Real-time Transport Protocol) media packets.

/// QoS (Quality of Service) class identifiers for dedicated bearers.
public enum QoSClass: Int, Sendable {
    /// QCI 1 — conversational voice (VoLTE).
    case voice = 1
}

/// Opaque handle returned when a dedicated bearer is granted.
public struct BearerHandle: Sendable, Hashable {
    public let id: UUID

    /// Creates a new unique bearer handle.
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Errors raised when bearer management is unavailable or a request fails.
public enum BearerAdapterError: Error, Sendable, CustomStringConvertible {
    case unavailable
    case requestFailed

    public var description: String {
        switch self {
        case .unavailable:
            return "Bearer management is not available"
        case .requestFailed:
            return "Dedicated bearer request failed"
        }
    }
}

/// Platform hook for requesting and releasing dedicated LTE bearers.
public protocol BearerAdapter: Sendable {
    /// Asks the modem for a dedicated bearer with the given QoS class.
    func requestDedicatedBearer(qci: QoSClass) throws -> BearerHandle
    /// Releases a previously granted bearer.
    func releaseBearer(_ handle: BearerHandle) throws
}
