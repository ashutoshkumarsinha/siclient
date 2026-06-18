import Foundation

public struct AKAChallengeResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case success(res: Data, ik: Data, ck: Data)
        case syncFailure(auts: Data)
        case invalidAUTN
    }

    public let status: Status

    public init(status: Status) {
        self.status = status
    }
}

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

public protocol SimAdapter: Sendable {
    func getIMPI() throws -> String
    func getIMPUList() throws -> [String]
    func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult
}
