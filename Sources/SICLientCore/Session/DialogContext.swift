import Foundation

public struct DialogContext: Sendable, Equatable {
    public var callID: String
    public var localTag: String
    public var remoteTag: String?
    public var localCSeq: Int
    public var remoteCSeq: Int?
    public var routeSet: [String]
    public var recordRoute: [String]
    public var remoteTarget: String?

    public init(
        callID: String = UUID().uuidString,
        localTag: String = String(UUID().uuidString.prefix(8)),
        remoteTag: String? = nil,
        localCSeq: Int = 1,
        remoteCSeq: Int? = nil,
        routeSet: [String] = [],
        recordRoute: [String] = [],
        remoteTarget: String? = nil
    ) {
        self.callID = callID
        self.localTag = localTag
        self.remoteTag = remoteTag
        self.localCSeq = localCSeq
        self.remoteCSeq = remoteCSeq
        self.routeSet = routeSet
        self.recordRoute = recordRoute
        self.remoteTarget = remoteTarget
    }

    public mutating func nextCSeq() -> Int {
        localCSeq += 1
        return localCSeq
    }
}

public enum SessionState: Sendable, Equatable {
    case idle
    case inviting
    case proceeding
    case preconditionWait
    case established
    case terminating
    case terminated
}

public struct SessionContext: Sendable, Equatable {
    public var dialog: DialogContext
    public var state: SessionState
    public var remoteURI: String
    public var localURI: String
    public var preconditionState: PreconditionState
    public var negotiatedCodec: AudioCodec?
    public var bearerHandle: BearerHandle?
    public var remoteMedia: MediaEndpoint?
    public var localAudioPort: Int?
    public var mediaDirection: MediaDirection

    public init(
        dialog: DialogContext,
        state: SessionState = .idle,
        remoteURI: String,
        localURI: String,
        preconditionState: PreconditionState = PreconditionState(),
        negotiatedCodec: AudioCodec? = nil,
        bearerHandle: BearerHandle? = nil,
        remoteMedia: MediaEndpoint? = nil,
        localAudioPort: Int? = nil,
        mediaDirection: MediaDirection = .sendrecv
    ) {
        self.dialog = dialog
        self.state = state
        self.remoteURI = remoteURI
        self.localURI = localURI
        self.preconditionState = preconditionState
        self.negotiatedCodec = negotiatedCodec
        self.bearerHandle = bearerHandle
        self.remoteMedia = remoteMedia
        self.localAudioPort = localAudioPort
        self.mediaDirection = mediaDirection
    }
}

public enum SessionError: Error, Sendable, CustomStringConvertible {
    case notRegistered
    case invalidDestination
    case signalingFailed(String)
    case preconditionTimeout
    case unexpectedResponse(Int)
    case noActiveSession
    case noPendingInvite
    case requestTimeout(String)
    case inviteCancelled
    case mediaFailed(String)
    case holdNotAllowed
    case concurrentCallLimit

    public var description: String {
        switch self {
        case .notRegistered: return "IMS registration required before placing a call"
        case .invalidDestination: return "Invalid call destination URI"
        case .signalingFailed(let reason): return "Session signaling failed: \(reason)"
        case .preconditionTimeout: return "QoS preconditions were not met in time"
        case .unexpectedResponse(let code): return "Unexpected SIP response: \(code)"
        case .noActiveSession: return "No active session"
        case .noPendingInvite: return "No INVITE in progress to cancel"
        case .requestTimeout(let method): return "Timed out waiting for \(method)"
        case .inviteCancelled: return "Call setup cancelled"
        case .mediaFailed(let reason): return "Media session failed: \(reason)"
        case .holdNotAllowed: return "Hold is only allowed on established calls"
        case .concurrentCallLimit: return "Maximum concurrent dialogs reached (1 active + 1 held)"
        }
    }
}
