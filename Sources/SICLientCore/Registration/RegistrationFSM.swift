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
    private var recoveryTask: Task<Void, Never>?
    private var lastNetworkPath: String?
    private var lastLocalIP: String?

    public init(profile: OperatorProfile, platform: PlatformContext, transport: any SIPTransport, logger: Logger) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
    }

    public func currentState() -> RegistrationState { state }
    public func registrationContext() -> RegistrationContext { context }

    public func register(expires: Int = 3600) async throws {
        var attempt = 0
        let maxAttempts = profile.resilience.maxRegistrationRetries

        while true {
            do {
                try await registerOnce(expires: expires)
                return
            } catch {
                attempt += 1
                let statusCode = Self.statusCode(from: error)
                guard RetryPolicy.shouldRetryRegistration(
                    statusCode: statusCode,
                    error: error,
                    attempt: attempt,
                    maxAttempts: maxAttempts
                ) else {
                    throw error
                }

                let delay = RetryPolicy.delayBeforeRetry(attempt: attempt - 1)
                logger.warn(
                    "Registration retry scheduled",
                    fields: [
                        "attempt": String(attempt),
                        "status": statusCode.map(String.init) ?? "transport",
                    ]
                )
                try await Task.sleep(for: delay)
            }
        }
    }

    public func handleNetworkPathChange() async throws {
        let access = try platform.accessInfo.currentAccessInfo()
        let path = NetworkResiliencePolicy.pathLabel(for: access)
        let ip = try platform.network.localIPAddress()

        defer {
            lastNetworkPath = path
            lastLocalIP = ip
        }

        guard state == .registered || state == .reregistering else { return }

        let pathChanged = lastNetworkPath.map {
            NetworkResiliencePolicy.shouldReregisterAfterIPChange(previousPath: $0, currentPath: path)
        } ?? false
        let ipChanged = lastLocalIP.map {
            NetworkResiliencePolicy.shouldReregisterAfterIPChange(previousIP: $0, currentIP: ip)
        } ?? false

        guard pathChanged || ipChanged else { return }

        logger.info(
            "Network change detected; forcing re-register",
            fields: ["path": path, "local_ip": ip]
        )
        refreshTask?.cancel()
        state = .reregistering
        try await register(expires: context.expiresSec)
    }

    private func registerOnce(expires: Int = 3600) async throws {
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
        lastNetworkPath = try? NetworkResiliencePolicy.pathLabel(for: platform.accessInfo.currentAccessInfo())
        lastLocalIP = try? platform.network.localIPAddress()
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
        recoveryTask?.cancel()
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
        scheduleNetworkRecovery()
    }

    private func scheduleNetworkRecovery() {
        recoveryTask?.cancel()
        let timeout = profile.resilience.networkRecoveryTimeoutSec
        recoveryTask = Task { [weak self] in
            let deadline = NetworkResiliencePolicy.networkRecoveryDeadline(timeoutSec: timeout)
            var attempt = 0
            while ContinuousClock.now < deadline, !Task.isCancelled {
                guard let self else { return }
                let delay = RetryPolicy.delayBeforeRetry(attempt: attempt)
                try? await Task.sleep(for: delay)
                attempt += 1
                do {
                    try await self.register(expires: self.context.expiresSec)
                    self.logger.info("Network recovery re-registration succeeded")
                    return
                } catch {
                    self.logger.warn("Network recovery attempt failed", fields: ["error": String(describing: error)])
                }
            }
        }
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
        do {
            let impus = try platform.sim.getIMPUList()
            guard let impu = impus.first else { return }
            let localIP = try platform.network.localIPAddress()
            let strategy = SIPKeepAlive.strategy(
                transport: transport,
                profile: profile,
                impu: impu,
                localIP: localIP,
                localPort: 5060,
                context: context
            )
            try await transport.send(SIPKeepAlive.payload(for: strategy))
            logger.trace(
                "Sent transport keep-alive",
                fields: ["mode": transport.isReliable ? "options" : "crlf"]
            )
        } catch {
            logger.warn("Keep-alive failed", fields: ["error": String(describing: error)])
        }
    }

    private static func statusCode(from error: Error) -> Int? {
        if case RegistrationError.unexpectedStatus(let code) = error { return code }
        if case ClientTransactionError.unexpectedResponse(let code) = error { return code }
        return nil
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
