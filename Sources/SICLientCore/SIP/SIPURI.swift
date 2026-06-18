import Foundation

// MARK: - File Overview
//
// SIP (Session Initiation Protocol) addresses look like email addresses with a scheme,
// e.g. `sip:alice@operator.com:5060`. This file defines the standard SIP methods used
// in VoLTE/IMS calls and a small parser/builder for SIP URIs (Uniform Resource Identifiers).

/// Standard SIP request methods used for registration, calls, and session control.
public enum SIPMethod: String, Sendable {
    // Registration and discovery
    case register = "REGISTER"
    case options = "OPTIONS"
    // Call setup and teardown
    case invite = "INVITE"
    case ack = "ACK"
    case cancel = "CANCEL"
    case bye = "BYE"
    // Mid-call session updates
    case update = "UPDATE"
    case prack = "PRACK"
    // Messaging and transfer
    case message = "MESSAGE"
    case refer = "REFER"
}

/// Parsed representation of a SIP URI such as `sip:user@host:port;param=value`.
public struct SIPURI: Sendable, Equatable {
    /// URI scheme, typically `sip` or `sips` (secure SIP).
    public var scheme: String
    /// User part before `@`, if present (often a phone number or IMPU).
    public var user: String?
    /// Hostname or IP address of the SIP server or endpoint.
    public var host: String
    /// Optional UDP/TCP/TLS port number.
    public var port: Int?
    /// Semicolon-separated URI parameters (e.g. transport, user=phone).
    public var parameters: [String: String]

    /// Creates a SIP URI from its components.
    public init(scheme: String = "sip", user: String? = nil, host: String, port: Int? = nil, parameters: [String: String] = [:]) {
        self.scheme = scheme
        self.user = user
        self.host = host
        self.port = port
        self.parameters = parameters
    }

    /// Serializes the URI back to its string form for use in SIP headers.
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

    /// Parses a raw SIP URI string into structured components; returns nil if malformed.
    public static func parse(_ raw: String) -> SIPURI? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeEnd = trimmed.firstIndex(of: ":") else { return nil }
        let scheme = String(trimmed[..<schemeEnd])
        var remainder = String(trimmed[trimmed.index(after: schemeEnd)...])

        // Extract `;param=value` suffix before splitting user@host
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
