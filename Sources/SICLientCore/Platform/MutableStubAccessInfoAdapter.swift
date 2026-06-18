import Foundation

public final class MutableStubAccessInfoAdapter: AccessInfoAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var accessInfo: AccessInfo

    public init(accessInfo: AccessInfo = AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "234150999010203")) {
        self.accessInfo = accessInfo
    }

    public func setAccessInfo(_ accessInfo: AccessInfo) {
        lock.lock()
        self.accessInfo = accessInfo
        lock.unlock()
    }

    public func currentAccessInfo() throws -> AccessInfo {
        lock.lock()
        defer { lock.unlock() }
        return accessInfo
    }
}
