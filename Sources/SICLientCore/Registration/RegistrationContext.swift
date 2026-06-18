import Foundation

// MARK: - File Overview
//
// Holds parsed data from a successful IMS registration (200 OK): the Service-Route
// to reach the S-CSCF, public identities (IMPU), expiry, and security association.
// Also builds REGISTER/OPTIONS requests and parses registration responses.

/// Mutable registration state accumulated across REGISTER exchanges.
public struct RegistrationContext: Sendable, Equatable {
    /// Service-Route header — next-hop URI for all subsequent SIP requests.
    public var serviceRoute: String?
    /// IMPU (IP Multimedia Public Identity) list from P-Associated-URI.
    public var associatedURIs: [String]
    /// Primary public identity used for outbound calls.
    public var defaultIMPU: String?
    /// Registration lifetime in seconds from Expires header.
    public var expiresSec: Int
    /// Call-ID reused for all REGISTER refreshes in this registration cycle.
    public var callID: String
    /// Monotonically increasing CSeq for each REGISTER sent.
    public var cseq: Int
    /// Security association negotiated via Security-Server/Security-Verify.
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

/// Registration lifecycle states managed by RegistrationFSM.
public enum RegistrationState: Sendable, Equatable {
    case unregistered
    case registering
    /// Waiting for IMS-AKA response after 401 challenge.
    case authenticating
    case registered
    /// Refreshing an existing registration before expiry.
    case reregistering
}

/// Errors during IMS registration or deregistration.
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

/// Builds SIP REGISTER and OPTIONS requests for IMS registration.
public enum RegisterRequestBuilder {
    /// Creates a SIP REGISTER to the home domain registrar (via P-CSCF).
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
            // Empty Digest placeholder triggers 401 with IMS-AKA challenge from network.
            headers.set("Authorization", value: #"Digest username="\#(impi)", realm="", nonce="", uri="\#(registrarURI)", response=""#)
        }

        return SIPRequest(method: SIPMethod.register.rawValue, requestURI: registrarURI, headers: headers)
    }

    /// Creates a SIP OPTIONS keep-alive request for reliable (TCP/TLS) transports.
    public static func makeOPTIONS(
        profile: OperatorProfile,
        impu: String,
        localIP: String,
        localPort: Int,
        context: RegistrationContext,
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
        headers.set("CSeq", value: "\(context.cseq + 1) OPTIONS")
        headers.set("Contact", value: IMSHeaderBuilder.contact(impu: impu, expires: context.expiresSec))
        headers.set("Allow", value: IMSHeaderBuilder.allowRegistration())

        if let securityAssociation, securityAssociation.isEstablished {
            headers.set("Security-Verify", value: securityAssociation.verifyValue)
        }

        return SIPRequest(method: SIPMethod.options.rawValue, requestURI: registrarURI, headers: headers)
    }
}

/// Parses successful and challenge responses from the IMS registrar.
public enum RegistrationResponseParser {
    /// Extracts Service-Route, IMPU list, expiry, and Security-Server from 200 OK.
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

    /// Parses WWW-Authenticate header from 401 into an IMS-AKA Digest challenge.
    public static func parse401(_ response: SIPResponse) throws -> DigestChallenge {
        guard let header = response.headers["WWW-Authenticate"], let challenge = DigestAuthParser.parseChallenge(header) else {
            throw RegistrationError.invalidChallenge("missing WWW-Authenticate")
        }
        return challenge
    }
}
