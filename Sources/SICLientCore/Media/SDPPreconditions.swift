import Foundation

// MARK: - File Overview
// Models QoS (Quality of Service) preconditions in SDP (Session Description Protocol).
// Preconditions let both call parties agree that network resources are ready before
// media starts flowing (RFC 3312).

/// Which side of the call a precondition applies to (us or the remote party).
public enum PreconditionDirection: String, Sendable, Equatable {
    case local
    case remote
}

/// How strictly a precondition must be met before the call proceeds.
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

    /// True when the precondition is fully satisfied for this direction.
    public var isMet: Bool {
        self == .sendrecv || self == .met
    }
}

/// One direction's QoS precondition status (local or remote).
public struct PreconditionSegment: Sendable, Equatable {
    public var direction: PreconditionDirection
    public var status: PreconditionStatus

    /// Creates a precondition segment for one call direction.
    public init(direction: PreconditionDirection, status: PreconditionStatus) {
        self.direction = direction
        self.status = status
    }
}

/// Combined local and remote QoS precondition state for an SDP session.
public struct PreconditionState: Sendable, Equatable {
    public var local: PreconditionStatus
    public var remote: PreconditionStatus

    /// Creates a precondition state, defaulting both sides to none.
    public init(local: PreconditionStatus = .none, remote: PreconditionStatus = .none) {
        self.local = local
        self.remote = remote
    }

    /// True when both local and remote preconditions are met.
    public var allMet: Bool {
        local.isMet && remote.isMet
    }

    /// Parses `a=curr:qos` attribute lines from SDP into a precondition state.
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

    /// Builds `a=curr:qos` SDP attribute lines for the current state.
    public func currAttributes() -> [String] {
        [
            "a=curr:qos local \(local.rawValue)",
            "a=curr:qos remote \(remote.rawValue)",
        ]
    }

    /// Builds desired and confirm QoS attribute lines when preconditions are enabled.
    public static func desiredAttributes(enabled: Bool) -> [String] {
        guard enabled else { return [] }
        return [
            "a=des:qos mandatory local sendrecv",
            "a=des:qos optional remote sendrecv",
            "a=conf:qos remote sendrecv",
        ]
    }
}
