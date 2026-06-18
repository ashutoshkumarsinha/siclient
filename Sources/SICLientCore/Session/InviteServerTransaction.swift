import Foundation

// MARK: - File Overview
//
// When we receive an incoming INVITE (mobile-terminated call), the server-side
// transaction sends provisional and final responses and waits for follow-up requests
// like PRACK, UPDATE, and ACK within the same dialog.

/// Errors while waiting for or handling in-dialog SIP requests on the server side.
public enum ServerTransactionError: Error, Sendable, CustomStringConvertible {
    case timeout(String)
    case unexpectedRequest(String)

    public var description: String {
        switch self {
        case .timeout(let method): return "Timed out waiting for \(method)"
        case .unexpectedRequest(let reason): return "Unexpected SIP request: \(reason)"
        }
    }
}

/// Sends responses and waits for in-dialog requests during an incoming INVITE flow.
public actor InviteServerTransaction {
    private let transport: any SIPTransport
    private let logger: Logger?
    private let t2: Duration

    public init(transport: any SIPTransport, logger: Logger? = nil, t2: Duration = .seconds(4)) {
        self.transport = transport
        self.logger = logger
        self.t2 = t2
    }

    /// Sends a SIP response (e.g. 100 Trying, 183 Session Progress, 200 OK) to the network.
    public func sendResponse(_ response: SIPResponse) async throws {
        let payload = SIPSerializer.serialize(.response(response))
        logSIP(direction: "out", payload: payload)
        try await transport.send(payload)
    }

    /// Blocks until a specific in-dialog request (PRACK, UPDATE, ACK) arrives or times out.
    public func waitForRequest(
        method: String,
        callID: String,
        timeout: Duration? = nil
    ) async throws -> SIPRequest {
        let wait = timeout ?? t2
        guard let request = try await receiveRequest(timeout: wait, callID: callID, method: method) else {
            throw ServerTransactionError.timeout(method)
        }
        return request
    }

    private func receiveRequest(
        timeout: Duration,
        callID: String,
        method: String
    ) async throws -> SIPRequest? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let remaining = deadline - ContinuousClock.now
            guard let data = try await transport.receive(timeout: remaining) else { return nil }
            guard let message = try? SIPParser.parse(data) else { continue }
            guard case .request(let request) = message else {
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
                continue
            }
            if request.headers["Call-ID"] != callID {
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
                continue
            }
            if request.method.caseInsensitiveCompare(method) != .orderedSame {
                if let loopback = transport as? LoopbackSIPTransport {
                    await loopback.requeue(data)
                }
                continue
            }
            logSIP(direction: "in", payload: data)
            return request
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
