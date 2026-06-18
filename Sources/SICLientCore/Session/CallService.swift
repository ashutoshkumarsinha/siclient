import Foundation

public actor CallService {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger

    private let registrationFSM: RegistrationFSM
    private let sessionFSM: SessionFSM

    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger,
        enableMedia: Bool = true,
        mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil
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

    public func handleNetworkPathChange() async throws {
        try await registrationFSM.handleNetworkPathChange()
    }
}
