import Foundation

// MARK: - File Overview
//
// NAT (Network Address Translation) bindings and UDP flows can go stale without traffic.
// SIP keep-alive sends periodic CRLF pings (UDP) or OPTIONS requests (TCP/TLS)
// to keep the path to the P-CSCF open while registered.

/// Strategy for keeping the SIP transport alive between registration refreshes.
public enum SIPKeepAliveStrategy: Sendable {
    /// Double CRLF ping for UDP — minimal overhead, no full SIP message.
    case crlf
    /// Full SIP OPTIONS for reliable transports (TCP/TLS).
    case options(SIPRequest)
}

/// Selects and builds keep-alive payloads based on transport type.
public enum SIPKeepAlive {
    /// Chooses CRLF for UDP or OPTIONS for TCP/TLS based on transport reliability.
    public static func strategy(
        transport: any SIPTransport,
        profile: OperatorProfile,
        impu: String,
        localIP: String,
        localPort: Int,
        context: RegistrationContext
    ) -> SIPKeepAliveStrategy {
        if transport.isReliable {
            let options = RegisterRequestBuilder.makeOPTIONS(
                profile: profile,
                impu: impu,
                localIP: localIP,
                localPort: localPort,
                context: context,
                securityAssociation: context.securityAssociation
            )
            return .options(options)
        }
        return .crlf
    }

    /// Serializes the keep-alive strategy to on-the-wire bytes.
    public static func payload(for strategy: SIPKeepAliveStrategy) -> Data {
        switch strategy {
        case .crlf:
            return Data("\r\n\r\n".utf8)
        case .options(let request):
            return SIPSerializer.serialize(.request(request))
        }
    }
}
