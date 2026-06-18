import Foundation

public struct StubAccessInfoAdapter: AccessInfoAdapter {
    private let accessInfo: AccessInfo

    public init(accessInfo: AccessInfo = AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "234150999010203")) {
        self.accessInfo = accessInfo
    }

    public func currentAccessInfo() throws -> AccessInfo {
        accessInfo
    }
}
