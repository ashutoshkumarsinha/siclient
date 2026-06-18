import Foundation

public struct RegistrationContext: Sendable, Equatable {
    public var serviceRoute: String?
    public var associatedURIs: [String]
    public var defaultIMPU: String?
    public var expiresSec: Int
    public var callID: String
    public var cseq: Int
    public var securityAssociation: SecurityAssociation?

    public init(
        serviceRoute: String? = nil,
        associatedURIs: [String] = [],
        defaultIMPU: String? = nil,
        expiresSec: Int = 3600,
        callID: String = UUID().uuidString,
        cseq: Int = 1,
        securityAssociation: SecurityAssociation? = nil
    ) {
        self.serviceRoute = serviceRoute
        self.associatedURIs = associatedURIs
        self.defaultIMPU = defaultIMPU
        self.expiresSec = expiresSec
        self.callID = callID
        self.cseq = cseq
        self.securityAssociation = securityAssociation
    }
}

public enum RegistrationState: Sendable, Equatable {
    case unregistered
    case registering
    case authenticating
    case registered
    case reregistering
}

public enum RegistrationError: Error, Sendable, CustomStringConvertible {
    case invalidChallenge(String)
    case akaFailed(String)
    case unexpectedStatus(Int)
    case securityRequired
    case notRegistered
    case simUnavailable

    public var description: String {
        switch self {
        case .invalidChallenge(let reason): return "Invalid IMS-AKA challenge: \(reason)"
        case .akaFailed(let reason): return "IMS-AKA failed: \(reason)"
        case .unexpectedStatus(let code): return "Unexpected SIP status: \(code)"
        case .securityRequired: return "Protected SIP required after initial REGISTER"
        case .notRegistered: return "Client is not registered"
        case .simUnavailable: return "SIM credentials unavailable"
        }
    }
}

public enum RegisterRequestBuilder {
    public static func makeRegister(
        profile: OperatorProfile,
        impi: String,
        impu: String,
        pani: String,
        localIP: String,
        localPort: Int,
        context: RegistrationContext,
        credentials: DigestCredentials? = nil,
        expires: Int = 3600,
        securityAssociation: SecurityAssociation? = nil
    ) -> SIPRequest {
        let registrarURI = "sip:\(profile.homeDomain)"
        let branch = "z9hG4bK-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let tag = UUID().uuidString.prefix(8)

        var headers = SIPHeaders()
        headers.set("Via", value: "SIP/2.0/UDP \(localIP):\(localPort);branch=\(branch);rport")
        headers.set("Max-Forwards", value: "70")
        headers.set("From", value: "<\(impu)>;tag=\(tag)")
        headers.set("To", value: "<\(impu)>")
        headers.set("Call-ID", value: context.callID)
        headers.set("CSeq", value: "\(context.cseq) REGISTER")
        headers.set("Contact", value: IMSHeaderBuilder.contact(impu: impu, expires: expires))
        headers.set("Expires", value: String(expires))
        headers.set("Supported", value: IMSHeaderBuilder.supportedRegistration())
        headers.set("Allow", value: IMSHeaderBuilder.allowRegistration())
        headers.set("P-Access-Network-Info", value: pani)
        headers.set("P-Preferred-Identity", value: impu)
        headers.set("P-Preferred-Service", value: IMSHeaderBuilder.preferredServiceMMTel())
        headers.set("Security-Client", value: SecurityHeaderBuilder.securityClient(mechanism: profile.security.mechanism))

        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }

        if let credentials {
            headers.set("Authorization", value: credentials.headerValue())
        } else {
            headers.set("Authorization", value: #"Digest username="\#(impi)", realm="", nonce="", uri="\#(registrarURI)", response=""#)
        }

        return SIPRequest(method: SIPMethod.register.rawValue, requestURI: registrarURI, headers: headers)
    }
}

public enum RegistrationResponseParser {
    public static func parse200OK(_ response: SIPResponse, profile: OperatorProfile) -> RegistrationContext {
        var context = RegistrationContext()
        context.serviceRoute = response.headers["Service-Route"]
        context.associatedURIs = response.headers.allValues("P-Associated-URI").flatMap { value in
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        context.defaultIMPU = context.associatedURIs.first ?? response.headers["To"]
        context.expiresSec = Int(response.headers["Expires"] ?? response.headers.first("Contact")?.value.components(separatedBy: "expires=").last?.split(separator: ";").first.map(String.init) ?? "3600") ?? 3600

        if let securityServer = response.headers["Security-Server"] {
            context.securityAssociation = SecurityAssociation(
                mechanism: profile.security.mechanism,
                serverValue: securityServer,
                verifyValue: SecurityHeaderBuilder.securityVerify(from: securityServer),
                isEstablished: true
            )
        }

        return context
    }

    public static func parse401(_ response: SIPResponse) throws -> DigestChallenge {
        guard let header = response.headers["WWW-Authenticate"], let challenge = DigestAuthParser.parseChallenge(header) else {
            throw RegistrationError.invalidChallenge("missing WWW-Authenticate")
        }
        return challenge
    }
}
