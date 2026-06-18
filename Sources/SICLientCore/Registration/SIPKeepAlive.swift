import Foundation

public enum SIPKeepAliveStrategy: Sendable {
    case crlf
    case options(SIPRequest)
}

public enum SIPKeepAlive {
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

    public static func payload(for strategy: SIPKeepAliveStrategy) -> Data {
        switch strategy {
        case .crlf:
            return Data("\r\n\r\n".utf8)
        case .options(let request):
            return SIPSerializer.serialize(.request(request))
        }
    }
}
