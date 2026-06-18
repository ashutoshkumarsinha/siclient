import Foundation

public enum RadioAccessTechnology: String, Sendable {
    case eutranFDD = "3GPP-E-UTRAN-FDD"
    case ieee80211 = "IEEE-802.11"
}

public struct AccessInfo: Sendable, Equatable {
    public let rat: RadioAccessTechnology
    public let cellOrAPIdentifier: String

    public init(rat: RadioAccessTechnology, cellOrAPIdentifier: String) {
        self.rat = rat
        self.cellOrAPIdentifier = cellOrAPIdentifier
    }

    public var paniHeaderValue: String {
        "\(rat.rawValue);utran-cell-id-3gpp=\(cellOrAPIdentifier)"
    }
}

public protocol AccessInfoAdapter: Sendable {
    func currentAccessInfo() throws -> AccessInfo
}
