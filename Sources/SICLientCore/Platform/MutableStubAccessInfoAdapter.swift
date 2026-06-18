import Foundation

// MARK: - File overview
//
// A thread-safe, mutable stub for AccessInfoAdapter. Tests can change the reported
// RAT (Radio Access Technology) and cell ID between SIP REGISTER attempts to simulate
// handovers (e.g. LTE to Wi-Fi).

/// Thread-safe stub that lets tests change the reported radio access info at runtime.
public final class MutableStubAccessInfoAdapter: AccessInfoAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var accessInfo: AccessInfo

    /// Starts with default LTE (E-UTRAN FDD) access info; override as needed in tests.
    public init(accessInfo: AccessInfo = AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "234150999010203")) {
        self.accessInfo = accessInfo
    }

    /// Updates the access info snapshot (e.g. to simulate a cell change).
    public func setAccessInfo(_ accessInfo: AccessInfo) {
        lock.lock()
        self.accessInfo = accessInfo
        lock.unlock()
    }

    /// Returns the current access info, safe to call from any thread.
    public func currentAccessInfo() throws -> AccessInfo {
        lock.lock()
        defer { lock.unlock() }
        return accessInfo
    }
}
