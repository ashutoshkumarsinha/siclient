import Foundation

// MARK: - File overview
//
// Defines how the client reports its radio access details to the IMS (IP Multimedia
// Subsystem) network. The P-Access-Network-Info (PANI) SIP header tells the P-CSCF
// whether the device is on LTE (E-UTRAN) or Wi-Fi and which cell or AP it is on.

/// Radio access technologies supported in PANI headers.
public enum RadioAccessTechnology: String, Sendable {
    /// LTE (Long Term Evolution) FDD mode — standard cellular VoLTE access.
    case eutranFDD = "3GPP-E-UTRAN-FDD"
    /// Wi-Fi access per IEEE 802.11.
    case ieee80211 = "IEEE-802.11"
}

/// Snapshot of the device's current radio access type and cell/AP identifier.
public struct AccessInfo: Sendable, Equatable {
    public let rat: RadioAccessTechnology
    public let cellOrAPIdentifier: String

    /// Creates access info from a RAT and a cell ID or access-point identifier.
    public init(rat: RadioAccessTechnology, cellOrAPIdentifier: String) {
        self.rat = rat
        self.cellOrAPIdentifier = cellOrAPIdentifier
    }

    /// Formats the value for a P-Access-Network-Info SIP header.
    public var paniHeaderValue: String {
        "\(rat.rawValue);utran-cell-id-3gpp=\(cellOrAPIdentifier)"
    }
}

/// Platform hook that reports the device's current radio access information.
public protocol AccessInfoAdapter: Sendable {
    /// Returns the current RAT and cell/AP identifier.
    func currentAccessInfo() throws -> AccessInfo
}
