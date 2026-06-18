import Foundation

// MARK: - File Overview
//
// IMS (IP Multimedia Subsystem) registration uses HTTP Digest authentication extended
// with AKA (Authentication and Key Agreement) from the SIM card. The network sends a
// challenge (401 Unauthorized + WWW-Authenticate); the client responds with computed
// credentials (Authorization header). This file parses/builds those headers and
// constructs IMS-specific security and registration headers.

/// Challenge sent by the IMS network in a 401 response (WWW-Authenticate header).
public struct DigestChallenge: Sendable, Equatable {
    /// Authentication realm — typically the operator home domain.
    public var realm: String
    /// Server nonce; must be echoed back in the Authorization response.
    public var nonce: String
    /// Hash algorithm (e.g. AKAv1-MD5 for IMS-AKA).
    public var algorithm: String?
    /// Quality of protection mode (typically `auth`).
    public var qop: String?
    /// Opaque server token echoed back unchanged.
    public var opaque: String?
    /// AUTN token from the network for IMS-AKA (Authentication Token Network).
    public var autn: String?

    public init(realm: String, nonce: String, algorithm: String? = nil, qop: String? = nil, opaque: String? = nil, autn: String? = nil) {
        self.realm = realm
        self.nonce = nonce
        self.algorithm = algorithm
        self.qop = qop
        self.opaque = opaque
        self.autn = autn
    }
}

/// Computed credentials sent in the Authorization header of an authenticated SIP request.
public struct DigestCredentials: Sendable, Equatable {
    public var username: String
    public var realm: String
    public var nonce: String
    public var uri: String
    public var response: String
    public var algorithm: String?
    public var cnonce: String?
    public var nc: String?
    public var qop: String?
    public var opaque: String?
    /// IMS-AKA synchronization failure token (TS 33.203). When set, `response` is omitted.
    public var auts: String?

    /// Formats credentials as a `Digest ...` Authorization header value.
    public func headerValue() -> String {
        var parts = [
            #"username="\#(username)""#,
            #"realm="\#(realm)""#,
            #"nonce="\#(nonce)""#,
            #"uri="\#(uri)""#,
        ]
        if let auts {
            // AUTS indicates SIM/network sync failure — no response hash is sent.
            parts.append(#"auts="\#(auts)""#)
        } else {
            parts.append(#"response="\#(response)""#)
        }
        if let algorithm { parts.append("algorithm=\(algorithm)") }
        if let cnonce { parts.append(#"cnonce="\#(cnonce)""#) }
        if let nc { parts.append("nc=\(nc)") }
        if let qop { parts.append(#"qop=\#(qop)"#) }
        if let opaque { parts.append(#"opaque="\#(opaque)""#) }
        return "Digest " + parts.joined(separator: ", ")
    }
}

/// Parses Digest authentication header values from SIP messages.
public enum DigestAuthParser {
    /// Parses a WWW-Authenticate challenge header into structured fields.
    public static func parseChallenge(_ headerValue: String) -> DigestChallenge? {
        guard let digestPart = extractDigestPart(headerValue) else { return nil }
        let params = parseParams(digestPart)
        guard let realm = params["realm"], let nonce = params["nonce"] else { return nil }
        return DigestChallenge(
            realm: realm,
            nonce: nonce,
            algorithm: params["algorithm"],
            qop: params["qop"],
            opaque: params["opaque"],
            autn: params["autn"]
        )
    }

    /// Parses an Authorization header into structured credential fields.
    public static func parseCredentials(_ headerValue: String) -> DigestCredentials? {
        guard let digestPart = extractDigestPart(headerValue) else { return nil }
        let params = parseParams(digestPart)
        guard
            let username = params["username"],
            let realm = params["realm"],
            let nonce = params["nonce"],
            let uri = params["uri"]
        else { return nil }

        let response = params["response"] ?? ""
        let auts = params["auts"]
        guard !response.isEmpty || auts != nil else { return nil }

        return DigestCredentials(
            username: username,
            realm: realm,
            nonce: nonce,
            uri: uri,
            response: response,
            algorithm: params["algorithm"],
            cnonce: params["cnonce"],
            nc: params["nc"],
            qop: params["qop"],
            opaque: params["opaque"],
            auts: params["auts"]
        )
    }

    private static func extractDigestPart(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let range = trimmed.range(of: "Digest", options: .caseInsensitive) {
            return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private static func parseParams(_ input: String) -> [String: String] {
        var result: [String: String] = [:]
        var current = input[...]
        while !current.isEmpty {
            current = current.drop(while: { $0 == "," || $0.isWhitespace })
            guard !current.isEmpty else { break }

            let keyEnd = current.firstIndex(where: { $0 == "=" || $0 == "," }) ?? current.endIndex
            let key = String(current[..<keyEnd]).trimmingCharacters(in: .whitespaces).lowercased()
            current = current[keyEnd...]

            guard current.first == "=" else { continue }
            current = current.dropFirst()

            let value: String
            if current.first == "\"" {
                // Quoted values may contain escaped characters.
                current = current.dropFirst()
                var escaped = false
                var collected = ""
                for ch in current {
                    if escaped {
                        collected.append(ch)
                        escaped = false
                        continue
                    }
                    if ch == "\\" {
                        escaped = true
                        continue
                    }
                    if ch == "\"" {
                        current = current.dropFirst(collected.count + 1)
                        break
                    }
                    collected.append(ch)
                }
                value = collected
            } else {
                let valueEnd = current.firstIndex(of: ",") ?? current.endIndex
                value = String(current[..<valueEnd]).trimmingCharacters(in: .whitespaces)
                current = current[valueEnd...]
            }

            result[key] = value
        }
        return result
    }
}

/// Builds Security-Client/Security-Verify headers for IMS media-plane protection.
public enum SecurityHeaderBuilder {
    /// Advertises the client's supported security mechanism to the P-CSCF (Proxy-CSCF).
    public static func securityClient(mechanism: SecurityMechanism, port: Int = 5061) -> String {
        switch mechanism {
        case .tls:
            return "tls; port=\(port)"
        case .ipsec3gpp:
            // IPsec (IP Security) parameters for 3GPP IMS media protection.
            return "ipsec-3gpp; alg=hmac-sha-1-96; ealg=null; spi-c=12345678; spi-s=87654321; port-c=5060; port-s=5061"
        }
    }

    /// Echoes the Security-Server value back as Security-Verify on subsequent requests.
    public static func securityVerify(from serverValue: String) -> String {
        serverValue
    }
}

/// Builds IMS-specific SIP headers required for VoLTE registration and calls.
public enum IMSHeaderBuilder {
    /// URN identifying the MMTel (Multimedia Telephony) service.
    public static func preferredServiceMMTel() -> String {
        "urn:urn-7:3gpp-service.ims.icsi.mmtel"
    }

    /// Contact header binding the IMPU (IP Multimedia Public Identity) with expiry and service tag.
    public static func contact(impu: String, expires: Int) -> String {
        "<\(impu)>;expires=\(expires);+g.3gpp.icsi-ref=\"\(preferredServiceMMTel())\""
    }

    /// Supported extensions for IMS registration (path routing, outbound, GRUU).
    public static func supportedRegistration() -> String {
        "path, outbound, gruu"
    }

    /// Methods the client supports during registration.
    public static func allowRegistration() -> String {
        "INVITE, ACK, OPTIONS, CANCEL, BYE, UPDATE, PRACK, REFER, NOTIFY, INFO, MESSAGE"
    }
}

/// Decodes IMS-AKA challenge tokens (RAND/AUTN) from a Digest challenge for SIM processing.
public enum IMSChallengeDecoder {
    /// Extracts RAND (random challenge) and AUTN from the network's Digest challenge.
    public static func randAndAUTN(from challenge: DigestChallenge) throws -> (rand: Data, autn: Data) {
        guard let rand = Data(base64Encoded: challenge.nonce) ?? Data(hexString: challenge.nonce) else {
            throw RegistrationError.invalidChallenge("nonce is not valid base64 or hex")
        }

        guard let autnRaw = challenge.autn else {
            throw RegistrationError.invalidChallenge("missing AUTN parameter")
        }

        if let autn = Data(hexString: autnRaw) {
            return (rand, autn)
        }
        if let autn = Data(base64Encoded: autnRaw) {
            return (rand, autn)
        }

        throw RegistrationError.invalidChallenge("AUTN is not valid hex or base64")
    }

    /// Base64-encodes the RES (Response) from the SIM for the Authorization header.
    public static func responseBase64(_ res: Data) -> String {
        res.base64EncodedString()
    }

    /// Base64-encodes AUTS for synchronization failure reporting to the network.
    public static func autsBase64(_ auts: Data) -> String {
        auts.base64EncodedString()
    }
}
