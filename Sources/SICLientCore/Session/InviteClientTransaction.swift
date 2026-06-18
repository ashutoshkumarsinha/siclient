import Foundation

public struct InviteTransactionResult: Sendable, Equatable {
    public var provisionals: [SIPResponse]
    public var final: SIPResponse

    public init(provisionals: [SIPResponse], final: SIPResponse) {
        self.provisionals = provisionals
        self.final = final
    }
}

public actor InviteClientTransaction {
    private let transport: any SIPTransport
    private let logger: Logger?
    private let t1: Duration
    private let t2: Duration

    public init(transport: any SIPTransport, logger: Logger? = nil, t1: Duration = .milliseconds(500), t2: Duration = .seconds(4)) {
        self.transport = transport
        self.logger = logger
        self.t1 = t1
        self.t2 = t2
    }

    public func sendInvite(
        _ invite: SIPRequest,
        prackBuilder: @Sendable @escaping (SIPResponse) -> SIPRequest?
    ) async throws -> InviteTransactionResult {
        logSIP(direction: "out", payload: SIPSerializer.serialize(.request(invite)))
        try await transport.send(SIPSerializer.serialize(.request(invite)))

        var provisionals: [SIPResponse] = []
        var finalResponse: SIPResponse?
        var attempt = 0
        let maxAttempts = transport.isReliable ? 1 : 7

        while attempt < maxAttempts, finalResponse == nil {
            let timeout = attempt == 0 ? t2 : min(t1 * (attempt + 1), t2)
            while let response = try await receiveResponse(timeout: timeout, callID: invite.headers["Call-ID"]) {
                logSIP(direction: "in", payload: SIPSerializer.serialize(.response(response)))

                if (100 ... 199).contains(response.statusCode) {
                    provisionals.append(response)
                    if response.statusCode == 183, requires100rel(response), let prack = prackBuilder(response) {
                        logSIP(direction: "out", payload: SIPSerializer.serialize(.request(prack)))
                        try await transport.send(SIPSerializer.serialize(.request(prack)))
                        _ = try await waitForPRACKResponse(prack: prack)
                    }
                    continue
                }

                if (200 ... 299).contains(response.statusCode),
                   response.headers["CSeq"]?.localizedCaseInsensitiveContains("INVITE") == true {
                    finalResponse = response
                    break
                }

                if (200 ... 299).contains(response.statusCode) {
                    if let loopback = transport as? LoopbackSIPTransport {
                        await loopback.requeue(SIPSerializer.serialize(.response(response)))
                    }
                    continue
                }

                if (300 ... 699).contains(response.statusCode) {
                    finalResponse = response
                    break
                }
            }

            if finalResponse == nil {
                try await transport.send(SIPSerializer.serialize(.request(invite)))
                attempt += 1
            }
        }

        guard let finalResponse else { throw ClientTransactionError.timeout }
        return InviteTransactionResult(provisionals: provisionals, final: finalResponse)
    }

    public func sendAck(_ ack: SIPRequest) async throws {
        logSIP(direction: "out", payload: SIPSerializer.serialize(.request(ack)))
        try await transport.send(SIPSerializer.serialize(.request(ack)))
    }

    public func sendRequest(_ request: SIPRequest) async throws -> SIPResponse {
        let transaction = ClientTransaction(transport: transport, logger: logger, t1: t1, t2: t2)
        return try await transaction.send(request)
    }

    private func waitForPRACKResponse(prack: SIPRequest) async throws -> SIPResponse? {
        let callID = prack.headers["Call-ID"]
        return try await receiveResponse(timeout: t2, callID: callID, matching: { response in
            response.statusCode == 200 && response.headers["CSeq"]?.contains("PRACK") == true
        })
    }

    private func receiveResponse(
        timeout: Duration,
        callID: String?,
        matching predicate: @Sendable (SIPResponse) -> Bool = { _ in true }
    ) async throws -> SIPResponse? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let remaining = deadline - ContinuousClock.now
            guard let data = try await transport.receive(timeout: remaining) else { return nil }
            guard let message = try? SIPParser.parse(data) else { continue }
            guard case .response(let response) = message else { continue }
            if let callID, response.headers["Call-ID"] != callID {
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
                continue
            }
            if predicate(response) { return response }
            if let loopback = transport as? LoopbackSIPTransport {
                await loopback.requeue(data)
            }
        }
        return nil
    }

    private func requires100rel(_ response: SIPResponse) -> Bool {
        let require = response.headers["Require"] ?? ""
        let unsupported = response.headers["Unsupported"] ?? ""
        return require.localizedCaseInsensitiveContains("100rel") && !unsupported.localizedCaseInsensitiveContains("100rel")
    }

    private func logSIP(direction: String, payload: Data) {
        guard let logger else { return }
        let text = SecretRedactor.redact(String(decoding: payload, as: UTF8.self))
        logger.debug("SIP trace", fields: ["direction": direction, "bytes": String(payload.count)])
        logger.trace(text)
    }
}
