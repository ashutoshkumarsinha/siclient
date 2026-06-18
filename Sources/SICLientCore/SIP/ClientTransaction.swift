import Foundation

public enum ClientTransactionState: Sendable, Equatable {
    case calling
    case proceeding
    case completed
    case terminated
}

public enum ClientTransactionError: Error, Sendable, CustomStringConvertible {
    case timeout
    case transportFailed(String)
    case unexpectedResponse(Int)

    public var description: String {
        switch self {
        case .timeout: return "SIP client transaction timed out"
        case .transportFailed(let reason): return "Transport failed: \(reason)"
        case .unexpectedResponse(let code): return "Unexpected SIP response: \(code)"
        }
    }
}

public actor ClientTransaction {
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

    public func send(
        _ request: SIPRequest,
        matching predicate: @Sendable @escaping (SIPResponse) -> Bool = { _ in true }
    ) async throws -> SIPResponse {
        var state: ClientTransactionState = .calling
        let payload = SIPSerializer.serialize(.request(request))
        logSIP(direction: "out", payload: payload)

        var lastResponse: SIPResponse?
        var attempt = 0
        let maxAttempts = transport.isReliable ? 1 : 7

        while attempt < maxAttempts {
            try await transport.send(payload)

            let receiveTimeout = attempt == 0 ? t1 : min(t1 * (attempt + 1), t2)
            if let response = try await receiveResponse(timeout: receiveTimeout, predicate: predicate) {
                logSIP(direction: "in", payload: SIPSerializer.serialize(.response(response)))
                lastResponse = response
                state = .proceeding

                if (100 ... 199).contains(response.statusCode) {
                    continue
                }

                state = .completed
                if !transport.isReliable, (200 ... 699).contains(response.statusCode) {
                    // ACK for non-INVITE not required; stop retransmits.
                }
                state = .terminated
                return response
            }

            attempt += 1
        }

        _ = state
        if let lastResponse { return lastResponse }
        throw ClientTransactionError.timeout
    }

    private func receiveResponse(
        timeout: Duration,
        predicate: @Sendable (SIPResponse) -> Bool
    ) async throws -> SIPResponse? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            let remaining = deadline - clock.now
            guard let data = try await transport.receive(timeout: remaining) else {
                return nil
            }
            guard let message = try? SIPParser.parse(data) else { continue }
            guard case .response(let response) = message else { continue }
            if predicate(response) {
                return response
            }
        }
        return nil
    }

    private func logSIP(direction: String, payload: Data) {
        guard let logger else { return }
        let text = SecretRedactor.redact(String(decoding: payload, as: UTF8.self))
        logger.debug("SIP trace", fields: ["direction": direction, "bytes": String(payload.count)])
        logger.trace(text)
    }
}
