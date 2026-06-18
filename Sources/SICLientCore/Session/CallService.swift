import Foundation

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

        Task {
            await registrationFSM.setRegistrationLostHandler { [weak self] in
                guard let self else { return }
                let context = await self.registrationFSM.registrationContext()
                await self.sessionFSM.terminateAllCalls(registration: context)
            }
        }
    }

    public func register(expires: Int = 3600) async throws {
        try await registrationFSM.register(expires: expires)
    }

    public func deregister() async throws {
        try await registrationFSM.deregister()
    }

    public func registrationState() async -> RegistrationState {
        await registrationFSM.currentState()
    }

    public func registrationContext() async -> RegistrationContext {
        await registrationFSM.registrationContext()
    }

    public func placeCall(to destinationURI: String) async throws -> SessionContext {
        let state = await registrationFSM.currentState()
        guard state == .registered || state == .reregistering else {
            throw SessionError.notRegistered
        }
        let context = await registrationFSM.registrationContext()
        return try await sessionFSM.originateCall(to: destinationURI, registration: context)
    }

    public func registerEmergency(expires: Int = 3600) async throws -> RegistrationContext {
        try await emergencyService.registerEmergency(expires: expires)
    }

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

    public func sendSMS(to destination: String, text: String) async throws {
        let context = await registrationFSM.registrationContext()
        try await smsService.sendSMS(to: destination, text: text, registration: context)
    }

    public func fetchCallForwarding() async throws -> CallForwardingRule {
        let impu = try await resolvedIMPU()
        return try await supplementaryClient.fetchCallForwarding(impu: impu)
    }

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

    public func beginESRVCCHandover() async throws {
        guard let callID = await sessionFSM.activeSessionContext()?.dialog.callID else {
            throw SessionError.noActiveSession
        }
        await handoverCoordinator.beginHandover(callID: callID)
    }

    public func completeESRVCCHandover() async throws {
        guard let callID = await sessionFSM.activeSessionContext()?.dialog.callID else {
            throw SessionError.noActiveSession
        }
        await handoverCoordinator.completeHandover(callID: callID)
    }

    public func handoverEvents() async -> [HandoverEvent] {
        handoverAdapter.snapshot()
    }

    public func hangUp() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.terminateActiveCall(registration: context)
    }

    public func hold() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.holdActiveCall(registration: context)
    }

    public func resume() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.resumeActiveCall(registration: context)
    }

    public func sendDTMF(_ digit: Character) async throws {
        try await sessionFSM.sendDTMF(digit)
    }

    public func mediaStats() async -> RTPStreamStats {
        await sessionFSM.mediaStats()
    }

    public func cancelCall() async throws {
        let context = await registrationFSM.registrationContext()
        try await sessionFSM.cancelPendingInvite(registration: context)
    }

    public func activeSession() async -> SessionContext? {
        await sessionFSM.activeSessionContext()
    }

    public func heldSession() async -> SessionContext? {
        await sessionFSM.heldSessionContext()
    }

    public func handleNetworkPathChange() async throws {
        try await registrationFSM.handleNetworkPathChange()
    }
}
