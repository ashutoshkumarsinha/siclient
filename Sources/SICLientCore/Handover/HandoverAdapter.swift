import Foundation

// MARK: - File Overview
// Handles voice call handover (eSRVCC — enhanced Single Radio Voice Call Continuity).
// Also attaches STIR/SHAKEN identity headers when enabled in the profile.

/// Events emitted during an eSRVCC handover attempt.
public enum HandoverEvent: Sendable, Equatable {
    case esrvccStarted(callID: String)
    case esrvccCompleted(callID: String)
    case esrvccFailed(callID: String, reason: String)
}

/// Receives notifications when a voice call handover starts, completes, or fails.
public protocol HandoverAdapter: Sendable {
    /// Called when a handover event occurs for an active call.
    func notifyHandover(_ event: HandoverEvent) async
}

/// Test double that records handover events in memory for inspection.
public final class StubHandoverAdapter: HandoverAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HandoverEvent] = []

    /// Creates an empty stub adapter.
    public init() {}

    /// Records a handover event thread-safely.
    public func notifyHandover(_ event: HandoverEvent) async {
        lock.withLock {
            events.append(event)
        }
    }

    /// Returns a copy of all recorded handover events.
    public func snapshot() -> [HandoverEvent] {
        lock.withLock { events }
    }
}

/// STIR/SHAKEN (Secure Telephone Identity Revisited / Signature-based Handling of
/// Asserted information using toKENs) policy helpers for attaching Identity headers.
public enum STIRSHAKPolicy {
    /// Returns the lab Identity header value from the profile, if STIR/SHAKEN is enabled.
    public static func identityHeader(for profile: OperatorProfile) -> String? {
        guard profile.services.handover.stirShakEnabled else { return nil }
        return profile.services.handover.labIdentityHeader
    }

    /// Adds an Identity header to SIP headers when STIR/SHAKEN is enabled.
    public static func attachIdentity(to headers: inout SIPHeaders, profile: OperatorProfile) {
        guard let identity = identityHeader(for: profile) else { return }
        headers.set("Identity", value: identity)
    }
}

/// Coordinates eSRVCC handover by notifying adapters and sending SIP REFER when needed.
public actor ESRVCCCoordinator {
    private let profile: OperatorProfile
    private let handoverAdapter: any HandoverAdapter
    private let transport: any SIPTransport
    private let logger: Logger
    private let sessionProvider: () async -> SessionContext?

    /// Creates a coordinator wired to profile, handover adapter, SIP transport, and session lookup.
    public init(
        profile: OperatorProfile,
        handoverAdapter: any HandoverAdapter,
        transport: any SIPTransport,
        logger: Logger,
        sessionProvider: @escaping () async -> SessionContext? = { nil }
    ) {
        self.profile = profile
        self.handoverAdapter = handoverAdapter
        self.transport = transport
        self.logger = logger
        self.sessionProvider = sessionProvider
    }

    /// Starts an eSRVCC handover for the given call and sends a REFER if a session exists.
    public func beginHandover(callID: String) async {
        guard profile.services.handover.esrvccEnabled else { return }
        await handoverAdapter.notifyHandover(.esrvccStarted(callID: callID))
        if let session = await sessionProvider() {
            await sendHandoverRefer(session: session, callID: callID)
        }
        logger.info("eSRVCC handover started", fields: ["call_id": callID])
    }

    /// Sends a SIP REFER to transfer the call leg during handover.
    private func sendHandoverRefer(session: SessionContext, callID: String) async {
        guard let target = session.dialog.remoteTarget else { return }
        var headers = SIPHeaders()
        headers.set("Refer-To", value: target)
        headers.set("Referred-By", value: session.localURI)
        headers.set("Call-ID", value: callID)
        let refer = SIPRequest(
            method: SIPMethod.refer.rawValue,
            requestURI: target,
            headers: headers,
            body: nil
        )
        try? await transport.send(SIPSerializer.serialize(.request(refer)))
    }

    /// Marks an eSRVCC handover as successfully completed.
    public func completeHandover(callID: String) async {
        guard profile.services.handover.esrvccEnabled else { return }
        await handoverAdapter.notifyHandover(.esrvccCompleted(callID: callID))
        logger.info("eSRVCC handover completed", fields: ["call_id": callID])
    }
}
