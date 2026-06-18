import Foundation

public enum QoSClass: Int, Sendable {
    case voice = 1
}

public struct BearerHandle: Sendable, Hashable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

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

public protocol BearerAdapter: Sendable {
    func requestDedicatedBearer(qci: QoSClass) throws -> BearerHandle
    func releaseBearer(_ handle: BearerHandle) throws
}
