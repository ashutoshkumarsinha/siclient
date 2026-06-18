import Foundation

public final class StubBearerAdapter: BearerAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var activeBearers: Set<UUID> = []

    public init() {}

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

    public func releaseBearer(_ handle: BearerHandle) throws {
        lock.lock()
        defer { lock.unlock() }
        guard activeBearers.remove(handle.id) != nil else {
            throw BearerAdapterError.requestFailed
        }
    }

    public var activeBearerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeBearers.count
    }
}
