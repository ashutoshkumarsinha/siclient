import Foundation

public enum EmergencyError: Error, Sendable, CustomStringConvertible {
    case disabled
    case registrationFailed(Int)

    public var description: String {
        switch self {
        case .disabled: return "Emergency IMS is disabled in profile"
        case .registrationFailed(let code): return "Emergency registration failed: \(code)"
        }
    }
}

public actor EmergencyService {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger
    private let sessionFSM: SessionFSM

    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger,
        sessionFSM: SessionFSM
    ) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
        self.sessionFSM = sessionFSM
    }

    public func registerEmergency(expires: Int = 3600) async throws -> RegistrationContext {
        guard profile.services.emergency.enabled else { throw EmergencyError.disabled }

        try await transport.connect()
        let transaction = ClientTransaction(transport: transport, logger: logger)
        let impi = try platform.sim.getIMPI()
        let impus = try platform.sim.getIMPUList()
        guard let impu = impus.first else { throw RegistrationError.simUnavailable }

        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        var context = RegistrationContext()

        let initial = EmergencyRequestBuilder.makeEmergencyRegister(
            profile: profile,
            impi: impi,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            context: context,
            credentials: nil,
            expires: expires
        )

        let challengeResponse = try await transaction.send(initial) { $0.statusCode == 401 || (200 ... 299).contains($0.statusCode) }
        if (200 ... 299).contains(challengeResponse.statusCode) {
            return RegistrationResponseParser.parse200OK(challengeResponse, profile: profile)
        }

        let challenge = try RegistrationResponseParser.parse401(challengeResponse)
        let (rand, autn) = try IMSChallengeDecoder.randAndAUTN(from: challenge)
        let akaResult = try platform.sim.akaChallenge(rand: rand, autn: autn)
        guard case .success(let res, _, _) = akaResult.status else {
            throw RegistrationError.akaFailed("emergency AKA failed")
        }

        context.cseq += 1
        let credentials = DigestCredentials(
            username: impi,
            realm: challenge.realm,
            nonce: challenge.nonce,
            uri: profile.services.emergency.sosURI.hasPrefix("sip:")
                ? profile.services.emergency.sosURI
                : "sip:sos@\(profile.homeDomain)",
            response: IMSChallengeDecoder.responseBase64(res),
            algorithm: challenge.algorithm ?? "AKAv1-MD5",
            cnonce: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            nc: "00000001",
            qop: challenge.qop ?? "auth",
            opaque: challenge.opaque
        )

        let authenticated = EmergencyRequestBuilder.makeEmergencyRegister(
            profile: profile,
            impi: impi,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            context: context,
            credentials: credentials,
            expires: expires
        )

        let final = try await transaction.send(authenticated) { (200 ... 299).contains($0.statusCode) }
        guard (200 ... 299).contains(final.statusCode) else {
            throw EmergencyError.registrationFailed(final.statusCode)
        }

        logger.info("Emergency IMS registration complete", fields: ["sos_uri": profile.services.emergency.sosURI])
        return RegistrationResponseParser.parse200OK(final, profile: profile)
    }

    public func placeEmergencyCall(
        to destinationURI: String? = nil,
        registration: RegistrationContext
    ) async throws -> SessionContext {
        guard profile.services.emergency.enabled else { throw EmergencyError.disabled }
        let target = destinationURI ?? "tel:\(profile.services.emergency.defaultNumber)"
        return try await sessionFSM.originateCall(to: target, registration: registration, emergency: true)
    }
}
