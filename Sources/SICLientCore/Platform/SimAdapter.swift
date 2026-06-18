import Foundation

// MARK: - File overview
//
// Defines the SIM (Subscriber Identity Module) interface for IMS (IP Multimedia
// Subsystem) authentication. The SIM provides IMPI/IMPU identities and answers
// AKA (Authentication and Key Agreement) challenges during SIP REGISTER.

/// Outcome of an AKA challenge against the SIM or lab vector store.
public struct AKAChallengeResult: Sendable, Equatable {
    /// Possible results from the SIM's AKA computation.
    public enum Status: Sendable, Equatable {
        /// Challenge succeeded — returns RES (response), IK (integrity key), CK (cipher key).
        case success(res: Data, ik: Data, ck: Data)
        /// Sequence mismatch — returns AUTS for network resynchronization.
        case syncFailure(auts: Data)
        /// The AUTN token from the network was invalid.
        case invalidAUTN
    }

    public let status: Status

    /// Wraps a single AKA status value.
    public init(status: Status) {
        self.status = status
    }
}

/// Errors raised when SIM credentials are missing or a challenge cannot be answered.
public enum SimAdapterError: Error, Sendable, CustomStringConvertible {
    case noCredentials
    case unsupportedChallenge

    public var description: String {
        switch self {
        case .noCredentials:
            return "SIM credentials are not available"
        case .unsupportedChallenge:
            return "No matching AKA vector for the provided RAND/AUTN"
        }
    }
}

/// Platform hook for reading IMS identities and running AKA authentication.
public protocol SimAdapter: Sendable {
    /// Returns the IMPI (IP Multimedia Private Identity) string.
    func getIMPI() throws -> String
    /// Returns all IMPU (IP Multimedia Public Identity) SIP URIs.
    func getIMPUList() throws -> [String]
    /// Computes the AKA response for the given RAND and AUTN challenge bytes.
    func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult
}
