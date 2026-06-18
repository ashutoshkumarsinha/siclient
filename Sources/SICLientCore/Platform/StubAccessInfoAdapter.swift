import Foundation

// MARK: - File overview
//
// A fixed stub for AccessInfoAdapter. Returns constant radio access details used in
// the P-Access-Network-Info (PANI) SIP header during IMS (IP Multimedia Subsystem)
// registration.

/// Returns a fixed RAT (Radio Access Technology) and cell ID for every query.
public struct StubAccessInfoAdapter: AccessInfoAdapter {
    private let accessInfo: AccessInfo

    /// Creates a stub with default LTE cell info; customize for specific test scenarios.
    public init(accessInfo: AccessInfo = AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "234150999010203")) {
        self.accessInfo = accessInfo
    }

    /// Always returns the access info provided at init time.
    public func currentAccessInfo() throws -> AccessInfo {
        accessInfo
    }
}
