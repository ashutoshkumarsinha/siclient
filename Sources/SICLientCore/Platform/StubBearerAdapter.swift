import Foundation

// MARK: - File overview
//
// A stub BearerAdapter for tests. In real LTE networks, a dedicated bearer with
// voice QCI (QoS Class Identifier) guarantees bandwidth for VoLTE (Voice over LTE)
// media. This stub pretends to grant and release those bearers.

/// Tracks fake dedicated bearer handles for voice QCI in unit tests.
public final class StubBearerAdapter: BearerAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var activeBearers: Set<UUID> = []

    /// Creates an empty bearer tracker.
    public init() {}

    /// Grants a dedicated bearer handle for voice traffic (QCI 1 only).
    public func requestDedicatedBearer(qci: QoSClass) throws -> BearerHandle {
        guard qci == .voice else {
            throw BearerAdapterError.requestFailed
        }

        let handle = BearerHandle()
        lock.lock()
        activeBearers.insert(handle.id)
        lock.unlock()
        return handle
    }

    /// Releases a previously granted bearer; fails if the handle is unknown.
    public func releaseBearer(_ handle: BearerHandle) throws {
        lock.lock()
        defer { lock.unlock() }
        guard activeBearers.remove(handle.id) != nil else {
            throw BearerAdapterError.requestFailed
        }
    }

    /// Number of bearers currently held (useful for test assertions).
    public var activeBearerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeBearers.count
    }
}
