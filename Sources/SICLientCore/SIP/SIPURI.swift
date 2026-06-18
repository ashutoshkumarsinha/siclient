import Foundation

public enum SIPMethod: String, Sendable {
    case register = "REGISTER"
    case invite = "INVITE"
    case options = "OPTIONS"
    case bye = "BYE"
    case ack = "ACK"
    case cancel = "CANCEL"
    case update = "UPDATE"
    case prack = "PRACK"
}

public struct SIPURI: Sendable, Equatable {
    public var scheme: String
    public var user: String?
    public var host: String
    public var port: Int?
    public var parameters: [String: String]

    public init(scheme: String = "sip", user: String? = nil, host: String, port: Int? = nil, parameters: [String: String] = [:]) {
        self.scheme = scheme
        self.user = user
        self.host = host
        self.port = port
        self.parameters = parameters
    }

    public var description: String {
        var value = "\(scheme):"
        if let user {
            value += user + "@"
        }
        value += host
        if let port {
            value += ":\(port)"
        }
        if !parameters.isEmpty {
            let params = parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";")
            value += ";\(params)"
        }
        return value
    }

    public static func parse(_ raw: String) -> SIPURI? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.firstIndex(of: ":") else { return nil }
        let scheme = String(trimmed[..<schemeEnd])
        var remainder = String(trimmed[trimmed.index(after: schemeEnd)...])

        var parameters: [String: String] = [:]
        if let paramIndex = remainder.firstIndex(of: ";") {
            let paramPart = String(remainder[paramIndex...].dropFirst())
            remainder = String(remainder[..<paramIndex])
            for token in paramPart.split(separator: ";") {
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    parameters[parts[0]] = parts[1]
                } else {
                    parameters[String(parts[0])] = ""
                }
            }
        }

        var user: String?
        var hostPort = remainder
        if let atIndex = remainder.firstIndex(of: "@") {
            user = String(remainder[..<atIndex])
            hostPort = String(remainder[remainder.index(after: atIndex)...])
        }

        let host: String
        let port: Int?
        if let colon = hostPort.firstIndex(of: ":") {
            host = String(hostPort[..<colon])
            port = Int(hostPort[hostPort.index(after: colon)...])
        } else {
            host = hostPort
            port = nil
        }

        guard !host.isEmpty else { return nil }
        return SIPURI(scheme: scheme, user: user, host: host, port: port, parameters: parameters)
    }
}
