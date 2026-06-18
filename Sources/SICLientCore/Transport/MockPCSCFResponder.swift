import Foundation

public final class MockPCSCFState: @unchecked Sendable {
    public var registered = false

    public init() {}
}

public enum MockPCSCFResponder {
    public static func response(
        for requestData: Data,
        profile: OperatorProfile,
        state: MockPCSCFState
    ) -> Data? {
        guard
            case .request(let request) = try? SIPParser.parse(requestData),
            request.method == SIPMethod.register.rawValue
        else { return nil }

        let expires = Int(request.headers["Expires"] ?? "3600") ?? 3600
        if expires == 0 {
            state.registered = false
            return SIPSerializer.serialize(.response(make200OK(for: request, profile: profile, expires: 0)))
        }

        if state.registered,
           let auth = request.headers["Authorization"],
           let creds = DigestAuthParser.parseCredentials(auth),
           !creds.response.isEmpty {
            return SIPSerializer.serialize(.response(make200OK(for: request, profile: profile, expires: expires)))
        }

        if let auth = request.headers["Authorization"],
           let creds = DigestAuthParser.parseCredentials(auth),
           !creds.response.isEmpty,
            validateCredentials(creds, profile: profile) {
            state.registered = true
            return SIPSerializer.serialize(.response(make200OK(for: request, profile: profile, expires: expires)))
        }

        return SIPSerializer.serialize(.response(make401(for: request, profile: profile)))
    }

    private static func validateCredentials(_ creds: DigestCredentials, profile: OperatorProfile) -> Bool {
        guard
            let labSim = profile.labSim,
            let vector = labSim.akaVectors.first,
            let expected = Data(hexString: vector.res)
        else { return false }

        guard let provided = Data(base64Encoded: creds.response) else { return false }
        return provided == expected
    }

    private static func make401(for request: SIPRequest, profile: OperatorProfile) -> SIPResponse {
        guard let labSim = profile.labSim, let vector = labSim.akaVectors.first else {
            return SIPResponse(statusCode: 403, reasonPhrase: "Forbidden")
        }

        let rand = Data(hexString: vector.rand) ?? Data()
        var headers = SIPHeaders()
        headers.set("Via", value: request.headers["Via"] ?? "")
        headers.set("From", value: request.headers["From"] ?? "")
        headers.set("To", value: request.headers["To"] ?? "")
        headers.set("Call-ID", value: request.headers["Call-ID"] ?? "")
        headers.set("CSeq", value: request.headers["CSeq"] ?? "")
        headers.set(
            "WWW-Authenticate",
            value: #"Digest realm="\#(profile.homeDomain)", nonce="\#(rand.base64EncodedString())", algorithm=AKAv1-MD5, qop="auth", autn="\#(vector.autn)""#
        )
        return SIPResponse(statusCode: 401, reasonPhrase: "Unauthorized - Challenging the UE", headers: headers)
    }

    private static func make200OK(for request: SIPRequest, profile: OperatorProfile, expires: Int) -> SIPResponse {
        let impu = profile.labSim?.impus.first ?? "sip:user@\(profile.homeDomain)"
        var headers = SIPHeaders()
        headers.set("Via", value: request.headers["Via"] ?? "")
        headers.set("From", value: request.headers["From"] ?? "")
        headers.set("To", value: "<\(impu)>;tag=\(UUID().uuidString.prefix(8))")
        headers.set("Call-ID", value: request.headers["Call-ID"] ?? "")
        headers.set("CSeq", value: request.headers["CSeq"] ?? "")
        headers.set("Expires", value: String(expires))
        headers.set("Service-Route", value: "<sip:pcscf.\(profile.homeDomain);lr>")
        headers.set("P-Associated-URI", value: "<\(impu)>")
        if profile.security.mechanism == .ipsec3gpp {
            headers.set("Security-Server", value: "ipsec-3gpp; alg=hmac-sha-1-96; ealg=null; spi-c=12345678; spi-s=87654321; port-c=5060; port-s=5061")
        } else {
            headers.set("Security-Server", value: "tls; port=5061")
        }
        return SIPResponse(statusCode: 200, reasonPhrase: "OK", headers: headers)
    }
}
