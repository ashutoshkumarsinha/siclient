import Foundation

public enum SMSRequestBuilder {
    public static func makeMESSAGE(
        profile: OperatorProfile,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        destinationURI: String,
        registration: RegistrationContext,
        text: String,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let body = Data(text.utf8)

        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(UUID().uuidString.prefix(8))")
        headers.set("To", value: "<\(destinationURI)>")
        headers.set("Call-ID", value: UUID().uuidString)
        headers.set("CSeq", value: "1 MESSAGE")
        headers.set("Contact", value: IMSHeaderBuilder.contact(impu: impu, expires: registration.expiresSec))
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("Accept-Contact", value: "*;+g.3gpp.icsi-ref=\"urn:urn-7:3gpp-service.ims.icsi.sms\"")
        headers.set("Content-Type", value: "text/plain")
        headers.set("Content-Length", value: String(body.count))
        if let serviceRoute = registration.serviceRoute {
            headers.set("Route", value: serviceRoute)
        }
        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }

        return SIPRequest(method: SIPMethod.message.rawValue, requestURI: destinationURI, headers: headers, body: body)
    }
}

public enum SMSError: Error, Sendable, CustomStringConvertible {
    case disabled
    case deliveryFailed(Int)

    public var description: String {
        switch self {
        case .disabled: return "SMS over IMS is disabled in profile"
        case .deliveryFailed(let code): return "SMS delivery failed: \(code)"
        }
    }
}

public actor SMSService {
    private let profile: OperatorProfile
    private let platform: PlatformContext
    private let transport: any SIPTransport
    private let logger: Logger

    public init(
        profile: OperatorProfile,
        platform: PlatformContext,
        transport: any SIPTransport,
        logger: Logger
    ) {
        self.profile = profile
        self.platform = platform
        self.transport = transport
        self.logger = logger
    }

    public func sendSMS(to destination: String, text: String, registration: RegistrationContext) async throws {
        guard profile.services.sms.enabled else { throw SMSError.disabled }

        let impu: String
        if let defaultIMPU = registration.defaultIMPU {
            impu = defaultIMPU
        } else if let first = try platform.sim.getIMPUList().first {
            impu = first
        } else {
            impu = ""
        }
        let pani = try platform.accessInfo.currentAccessInfo().paniHeaderValue
        let localIP = try platform.network.localIPAddress()
        let requestURI = destination.hasPrefix("sip:") || destination.hasPrefix("tel:")
            ? destination
            : "tel:\(destination)"

        let body = profile.services.sms.use3GPPPayload
            ? SMSPayloadBuilder.rpData(userData: text, destination: requestURI)
            : Data(text.utf8)

        var message = SMSRequestBuilder.makeMESSAGE(
            profile: profile,
            impu: impu,
            pani: pani,
            localIP: localIP,
            localPort: 5060,
            destinationURI: requestURI,
            registration: registration,
            text: text,
            securityAssociation: registration.securityAssociation
        )
        message.body = body
        message.headers.set("Content-Type", value: profile.services.sms.use3GPPPayload
            ? "application/vnd.3gpp.sms"
            : "text/plain")
        message.headers.set("Content-Length", value: String(body.count))

        let transaction = ClientTransaction(transport: transport, logger: logger)
        let response = try await transaction.send(message) { (200 ... 299).contains($0.statusCode) }
        guard (200 ... 299).contains(response.statusCode) else {
            throw SMSError.deliveryFailed(response.statusCode)
        }

        logger.info("SMS sent over IMS", fields: ["destination": requestURI, "bytes": String(text.utf8.count)])
    }
}
