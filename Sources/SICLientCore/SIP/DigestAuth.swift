import Foundation

public struct DigestChallenge: Sendable, Equatable {
    public var realm: String
    public var nonce: String
    public var algorithm: String?
    public var qop: String?
    public var opaque: String?
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

    public func headerValue() -> String {
        var parts = [
            #"username="\#(username)""#,
            #"realm="\#(realm)""#,
            #"nonce="\#(nonce)""#,
            #"uri="\#(uri)""#,
        ]
        if let auts {
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

public enum DigestAuthParser {
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

public enum SecurityHeaderBuilder {
    public static func securityClient(mechanism: SecurityMechanism, port: Int = 5061) -> String {
        switch mechanism {
        case .tls:
            return "tls; port=\(port)"
        case .ipsec3gpp:
            return "ipsec-3gpp; alg=hmac-sha-1-96; ealg=null; spi-c=12345678; spi-s=87654321; port-c=5060; port-s=5061"
        }
    }

    public static func securityVerify(from serverValue: String) -> String {
        serverValue
    }
}

public enum IMSHeaderBuilder {
    public static func preferredServiceMMTel() -> String {
        "urn:urn-7:3gpp-service.ims.icsi.mmtel"
    }

    public static func contact(impu: String, expires: Int) -> String {
        "<\(impu)>;expires=\(expires);+g.3gpp.icsi-ref=\"\(preferredServiceMMTel())\""
    }

    public static func supportedRegistration() -> String {
        "path, outbound, gruu"
    }

    public static func allowRegistration() -> String {
        "INVITE, ACK, OPTIONS, CANCEL, BYE, UPDATE, PRACK, REFER, NOTIFY, INFO, MESSAGE"
    }
}

public enum IMSChallengeDecoder {
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

    public static func responseBase64(_ res: Data) -> String {
        res.base64EncodedString()
    }

    public static func autsBase64(_ auts: Data) -> String {
        auts.base64EncodedString()
    }
}
