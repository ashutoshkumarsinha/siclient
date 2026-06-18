import Foundation

public enum PreconditionDirection: String, Sendable, Equatable {
    case local
    case remote
}

public enum PreconditionStrength: String, Sendable, Equatable {
    case mandatory
    case optional
}

/// RFC 3312 QoS precondition status token.
public enum PreconditionStatus: String, Sendable, Equatable {
    case none
    case send
    case recv
    case sendrecv
    case met

    public var isMet: Bool {
        self == .sendrecv || self == .met
    }
}

public struct PreconditionSegment: Sendable, Equatable {
    public var direction: PreconditionDirection
    public var status: PreconditionStatus

    public init(direction: PreconditionDirection, status: PreconditionStatus) {
        self.direction = direction
        self.status = status
    }
}

public struct PreconditionState: Sendable, Equatable {
    public var local: PreconditionStatus
    public var remote: PreconditionStatus

    public init(local: PreconditionStatus = .none, remote: PreconditionStatus = .none) {
        self.local = local
        self.remote = remote
    }

    public var allMet: Bool {
        local.isMet && remote.isMet
    }

    public static func parse(from attributes: [String]) -> PreconditionState {
        var state = PreconditionState()
        for attribute in attributes {
            let raw = attribute.hasPrefix("a=") ? String(attribute.dropFirst(2)) : attribute
            let tokens = raw.split(separator: " ").map(String.init)
            guard tokens.first == "curr:qos", tokens.count >= 3 else { continue }
            guard let direction = PreconditionDirection(rawValue: tokens[1]),
                  let status = PreconditionStatus(rawValue: tokens[2]) else { continue }
            switch direction {
            case .local: state.local = status
            case .remote: state.remote = status
            }
        }
        return state
    }

    public func currAttributes() -> [String] {
        [
            "a=curr:qos local \(local.rawValue)",
            "a=curr:qos remote \(remote.rawValue)",
        ]
    }

    public static func desiredAttributes(enabled: Bool) -> [String] {
        guard enabled else { return [] }
        return [
            "a=des:qos mandatory local sendrecv",
            "a=des:qos optional remote sendrecv",
            "a=conf:qos remote sendrecv",
        ]
    }
}
