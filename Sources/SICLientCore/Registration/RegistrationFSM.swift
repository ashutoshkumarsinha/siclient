import Foundation

public actor RegistrationFSM {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger

    private var state: RegistrationState = .unregistered
    private var context = RegistrationContext()
    private var lastCredentials: DigestCredentials?
    private var refreshTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    public init(profile: OperatorProfile, platform: PlatformContext, transport: any SIPTransport, logger: Logger) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
    }

    public func currentState() -> RegistrationState { state }
    public func registrationContext() -> RegistrationContext { context }

    public func register(expires: Int = 3600) async throws {
        switch state {
        case .unregistered:
            state = .registering
        case .registered, .reregistering:
            state = .reregistering
        default:
            break
        }

        try await transport.connect()
        let transaction = ClientTransaction(transport: transport, logger: logger)

        let impi = try platform.sim.getIMPI()
        let impus = try platform.sim.getIMPUList()
        guard let impu = impus.first else { throw RegistrationError.simUnavailable }

        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()

        context.cseq += 1

        if let lastCredentials, state == .reregistering || expires == 0 {
            let request = buildRegister(
                impi: impi, impu: impu, pani: pani, localIP: localIP,
                expires: expires, credentials: lastCredentials
            )
            let response = try await transaction.send(request) { (200 ... 299).contains($0.statusCode) || $0.statusCode == 403 }
            try await handleFinalResponse(response, expires: expires)
            return
        }

        let initial = buildRegister(
            impi: impi, impu: impu, pani: pani, localIP: localIP,
            expires: expires, credentials: nil
        )

        let firstResponse = try await transaction.send(initial) { response in
            response.statusCode == 401
                || response.statusCode == 403
                || (200 ... 299).contains(response.statusCode)
        }

        if firstResponse.statusCode == 200 {
            try await handleFinalResponse(firstResponse, expires: expires)
            return
        }

        guard firstResponse.statusCode == 401 else {
            let action = SIPErrorMapper.action(for: firstResponse.statusCode, method: SIPMethod.register.rawValue)
            if firstResponse.statusCode == 403 || action == .stop {
                state = .unregistered
                lastCredentials = nil
            }
            throw RegistrationError.unexpectedStatus(firstResponse.statusCode)
        }

        state = .authenticating
        let challenge = try RegistrationResponseParser.parse401(firstResponse)
        let (rand, autn) = try IMSChallengeDecoder.randAndAUTN(from: challenge)
        let akaResult = try platform.sim.akaChallenge(rand: rand, autn: autn)

        let credentials: DigestCredentials
        switch akaResult.status {
        case .success(let res, _, _):
            credentials = DigestCredentials(
                username: impi,
                realm: challenge.realm,
                nonce: challenge.nonce,
                uri: "sip:\(profile.homeDomain)",
                response: IMSChallengeDecoder.responseBase64(res),
                algorithm: challenge.algorithm ?? "AKAv1-MD5",
                cnonce: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                nc: "00000001",
                qop: challenge.qop ?? "auth",
                opaque: challenge.opaque
            )
            lastCredentials = credentials
        case .syncFailure:
            throw RegistrationError.akaFailed("AUTS sync failure")
        case .invalidAUTN:
            throw RegistrationError.akaFailed("invalid AUTN")
        }

        context.cseq += 1
        let authenticated = buildRegister(
            impi: impi, impu: impu, pani: pani, localIP: localIP,
            expires: expires, credentials: credentials
        )

        try SecurityPolicy.assertProtected(
            mechanism: profile.security.mechanism,
            isInitialRegister: false,
            hasSecurityVerify: authenticated.headers["Security-Verify"] != nil
        )

        let finalResponse = try await transaction.send(authenticated) { response in
            (200 ... 299).contains(response.statusCode) || response.statusCode == 403
        }

        try await handleFinalResponse(finalResponse, expires: expires)
    }

    private func buildRegister(
        impi: String,
        impu: String,
        pani: String,
        localIP: String,
        expires: Int,
        credentials: DigestCredentials?
    ) -> SIPRequest {
        RegisterRequestBuilder.makeRegister(
            profile: profile,
            impi: impi,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            context: context,
            credentials: credentials,
            expires: expires,
            securityAssociation: context.securityAssociation
        )
    }

    private func handleFinalResponse(_ response: SIPResponse, expires: Int) async throws {
        guard (200 ... 299).contains(response.statusCode) else {
            if response.statusCode == 403 {
                state = .unregistered
                context.securityAssociation = nil
                lastCredentials = nil
            }
            throw RegistrationError.unexpectedStatus(response.statusCode)
        }

        if expires == 0 {
            state = .unregistered
            context = RegistrationContext()
            lastCredentials = nil
            await transport.close()
            logger.info("Deregistered from IMS")
            return
        }

        context = RegistrationResponseParser.parse200OK(response, profile: profile)
        state = .registered
        scheduleRefresh()
        startKeepAlive()
        logRegistered()
    }

    public func deregister() async throws {
        guard state == .registered || state == .reregistering else {
            throw RegistrationError.notRegistered
        }

        refreshTask?.cancel()
        keepAliveTask?.cancel()
        state = .reregistering
        try await register(expires: 0)
    }

  private func scheduleRefresh() {
        refreshTask?.cancel()
        let refreshDelay = max(1, Int(Double(context.expiresSec) * profile.timers.registrationRefreshRatio))
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(refreshDelay))
            guard let self, !Task.isCancelled else { return }
            do {
                try await self.register(expires: self.context.expiresSec)
                self.logger.info("Re-registration succeeded")
            } catch {
                await self.handleReregisterFailure(error)
            }
        }
    }

    private func handleReregisterFailure(_ error: Error) {
        logger.warn("Re-registration failed", fields: ["error": String(describing: error)])
        state = .unregistered
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        let interval = profile.timers.keepaliveSec
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.sendKeepAlive()
            }
        }
    }

    private func sendKeepAlive() async {
        guard state == .registered else { return }
        let payload = Data("\r\n\r\n".utf8)
        do {
            try await transport.send(payload)
            logger.trace("Sent transport keep-alive")
        } catch {
            logger.warn("Keep-alive failed", fields: ["error": String(describing: error)])
        }
    }

    private func logRegistered() {
        logger.info(
            "IMS registration complete",
            fields: [
                "state": "registered",
                "service_route": context.serviceRoute ?? "",
                "default_impu": context.defaultIMPU ?? "",
                "expires": String(context.expiresSec),
                "security": profile.security.mechanism.rawValue,
            ]
        )
    }
}
