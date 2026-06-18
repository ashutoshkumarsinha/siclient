import Foundation

// MARK: - File Overview
//
// A SIP dialog is the long-lived context for a single call. It ties together Call-ID,
// tags, CSeq numbers, and routing information so follow-up messages (ACK, BYE, re-INVITE)
// reach the right party. This file holds that dialog state and the call session lifecycle.

/// Identifiers and routing state for one SIP dialog (one phone call).
public struct DialogContext: Sendable, Equatable {
    /// Unique call identifier shared by all messages in this dialog.
    public var callID: String
    /// Tag assigned by the local endpoint in the From header.
    public var localTag: String
    /// Tag assigned by the remote endpoint in the To header, set after first response.
    public var remoteTag: String?
    /// Local command sequence number; incremented for each new request we send.
    public var localCSeq: Int
    /// Remote CSeq from the last request they sent us.
    public var remoteCSeq: Int?
    /// Ordered list of Route headers for in-dialog requests (derived from Record-Route).
    public var routeSet: [String]
    /// Record-Route headers from the 200 OK, stored for building the route set.
    public var recordRoute: [String]
    /// Remote party's Contact URI — target for in-dialog requests like BYE.
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

    /// Increments and returns the next local CSeq for a new in-dialog request.
    public mutating func nextCSeq() -> Int {
        localCSeq += 1
        return localCSeq
    }
}

/// High-level call session states tracked by the session FSM (Finite State Machine).
public enum SessionState: Sendable, Equatable {
    case idle
    /// Outgoing INVITE sent, awaiting responses.
    case inviting
    /// Provisional responses received (ringing, session progress).
    case proceeding
    /// Waiting for QoS (Quality of Service) preconditions before answering.
    case preconditionWait
    /// Call is connected and media may be active.
    case established
    /// BYE sent or received; tearing down.
    case terminating
    /// Call fully ended.
    case terminated
}

/// Runtime context for an active or in-progress call session.
public struct SessionContext: Sendable, Equatable {
    public var dialog: DialogContext
    public var state: SessionState
    /// URI of the remote party (caller or callee).
    public var remoteURI: String
    /// Our public identity (IMPU) used in this call.
    public var localURI: String
    /// QoS precondition negotiation state for VoLTE.
    public var preconditionState: PreconditionState
    /// Audio codec agreed during SDP (Session Description Protocol) exchange.
    public var negotiatedCodec: AudioCodec?
    /// Dedicated bearer (data channel) reserved for voice traffic.
    public var bearerHandle: BearerHandle?
    /// Remote RTP (Real-time Transport Protocol) endpoint after SDP negotiation.
    public var remoteMedia: MediaEndpoint?
    public var localAudioPort: Int?
    /// Current media direction (send/receive/hold).
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

/// Errors that can occur during call setup, hold, or teardown.
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
