import Foundation

// MARK: - File Overview
//
// CallService is the top-level API that wires together IMS registration, call control,
// SMS, emergency calls, supplementary services (XCAP), and handover (eSRVCC).
// App code typically creates one CallService and calls register() then placeCall().

/// Facade over registration, session, emergency, SMS, and supplementary IMS services.
public actor CallService {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger

    private let registrationFSM: RegistrationFSM
    private let sessionFSM: SessionFSM
    private let emergencyService: EmergencyService
    private let smsService: SMSService
    private let supplementaryClient: SupplementaryServicesClient
    private let handoverCoordinator: ESRVCCCoordinator
    private let handoverAdapter: StubHandoverAdapter

    /// Creates the service graph: registration FSM, session FSM, and auxiliary clients.
    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger,
        enableMedia: Bool = true,
        mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil,
        xcapTransport: (any XCAPTransport)? = nil,
        handoverAdapter: StubHandoverAdapter? = nil
    ) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
        self.registrationFSM = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)
        let factory: (@Sendable () -> any RTPTransport)? = enableMedia
            ? (mediaTransportFactory ?? MediaBootstrap.rtpTransportFactory(profile: profile))
            : nil
        self.sessionFSM = SessionFSM(
            profile: profile,
            platform: platform,
            transport: transport,
            logger: logger,
            mediaTransportFactory: factory
        )
        self.emergencyService = EmergencyService(
            profile: profile,
            platform: platform,
            transport: transport,
            logger: logger,
            sessionFSM: sessionFSM
        )
        self.smsService = SMSService(profile: profile, platform: platform, transport: transport, logger: logger)
        self.supplementaryClient = SupplementaryServicesClient(
            profile: profile,
            transport: xcapTransport ?? InMemoryXCAPTransport(),
            logger: logger
        )
        let adapter = handoverAdapter ?? StubHandoverAdapter()
        self.handoverAdapter = adapter
        self.handoverCoordinator = ESRVCCCoordinator(
            profile: profile,
            handoverAdapter: adapter,
            transport: transport,
            logger: logger,
            sessionProvider: { [sessionFSM] in
                await sessionFSM.activeSessionContext()
            }
        )

        // When registration is lost, tear down any active calls immediately.
        Task {
            await registrationFSM.setRegistrationLostHandler { [weak self] in
                guard let self else { return }
                let context = await self.registrationFSM.registrationContext()
                await self.sessionFSM.terminateAllCalls(registration: context)
            }
        }
    }

    /// Registers with the IMS network using the operator profile (SIP REGISTER + IMS-AKA).
    public func register(expires: Int = 3600) async throws {
        try await registrationFSM.register(expires: expires)
    }

    /// Sends REGISTER with Expires: 0 to unregister from IMS.
    public func deregister() async throws {
        try await registrationFSM.deregister()
    }

    /// Current registration state (unregistered, registering, registered, etc.).
    public func registrationState() async -> RegistrationState {
        await registrationFSM.currentState()
    }

    /// Parsed registration data: service route, IMPU, security association, expiry.
    public func registrationContext() async -> RegistrationContext {
        await registrationFSM.registrationContext()
    }

    /// Places an outgoing VoLTE call (SIP INVITE) to the given SIP or tel URI.
    public func placeCall(to destinationURI: String) async throws -> SessionContext {
        let state = await registrationFSM.currentState()
        guard state == .registered || state == .reregistering else {
            throw SessionError.notRegistered
        }
        let context = await registrationFSM.registrationContext()
        return try await sessionFSM.originateCall(to: destinationURI, registration: context)
    }

    /// Performs emergency IMS registration (may bypass normal auth constraints).
    public func registerEmergency(expires: Int = 3600) async throws -> RegistrationContext {
        try await emergencyService.registerEmergency(expires: expires)
    }

    /// Places an emergency call (defaults to tel:112 if no destination given).
    public func placeEmergencyCall(
        to destinationURI: String? = nil,
        registration: RegistrationContext? = nil
    ) async throws -> SessionContext {
        let context: RegistrationContext
        if let registration {
            context = registration
        } else {
            context = await registrationFSM.registrationContext()
        }
        return try await emergencyService.placeEmergencyCall(to: destinationURI, registration: context)
    }

    /// Sends an SMS (Short Message Service) over IMS SIP MESSAGE.
    public func sendSMS(to destination: String, text: String) async throws {
        let context = await registrationFSM.registrationContext()
        try await smsService.sendSMS(to: destination, text: text, registration: context)
    }

    /// Reads unconditional call forwarding settings via XCAP (XML Configuration Access Protocol).
    public func fetchCallForwarding() async throws -> CallForwardingRule {
        let impu = try await resolvedIMPU()
        return try await supplementaryClient.fetchCallForwarding(impu: impu)
    }

    /// Enables or disables call forwarding to the given target via XCAP.
    public func setCallForwarding(active: Bool, target: String?) async throws {
        let impu = try await resolvedIMPU()
        try await supplementaryClient.setCallForwarding(
            impu: impu,
            rule: CallForwardingRule(active: active, target: target)
        )
    }

    private func resolvedIMPU() async throws -> String {
        if let impu = await registrationFSM.registrationContext().defaultIMPU {
            return impu
        }
        if let impu = try platform.sim.getIMPUList().first {
            return impu
        }
        return ""
    }

    /// Starts eSRVCC (enhanced Single Radio Voice Call Continuity) handover to CS domain.
    public func beginESRVCCHandover() async throws {
        guard let callID = await sessionFSM.activeSessionContext()?.dialog.callID else {
            throw SessionError.noActiveSession
        }
        await handoverCoordinator.beginHandover(callID: callID)
    }

    /// Completes eSRVCC handover after the radio/access switch finishes.
    public func completeESRVCCHandover() async throws {
        guard let callID = await sessionFSM.activeSessionContext()?.dialog.callID else {
            throw SessionError.noActiveSession
        }
        await handoverCoordinator.completeHandover(callID: callID)
    }

    /// Returns recorded handover events from the stub adapter (testing/diagnostics).
    public func handoverEvents() async -> [HandoverEvent] {
        handoverAdapter.snapshot()
    }

    /// Hangs up the active call (SIP BYE) and resumes a held call if one exists.
    public func hangUp() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.terminateActiveCall(registration: context)
    }

    /// Puts the active call on hold (re-INVITE with sendonly media direction).
    public func hold() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.holdActiveCall(registration: context)
    }

    /// Resumes a held call (re-INVITE with sendrecv media direction).
    public func resume() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.resumeActiveCall(registration: context)
    }

    /// Sends an in-band DTMF (Dual-Tone Multi-Frequency) tone during an active call.
    public func sendDTMF(_ digit: Character) async throws {
        try await sessionFSM.sendDTMF(digit)
    }

    /// Returns RTP packet statistics for the active media session.
    public func mediaStats() async -> RTPStreamStats {
        await sessionFSM.mediaStats()
    }

    /// Cancels an in-progress outgoing INVITE before the call is answered.
    public func cancelCall() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.cancelPendingInvite(registration: context)
    }

    /// Returns the currently active (connected or ringing) call session, if any.
    public func activeSession() async -> SessionContext? {
        await sessionFSM.activeSessionContext()
    }

    /// Returns a call session held while a second call is active, if any.
    public func heldSession() async -> SessionContext? {
        await sessionFSM.heldSessionContext()
    }

    /// Re-registers when the network path or local IP address changes (Wi-Fi ↔ cellular).
    public func handleNetworkPathChange() async throws {
        try await registrationFSM.handleNetworkPathChange()
    }
}
