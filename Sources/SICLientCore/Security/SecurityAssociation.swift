import Foundation

// MARK: - File overview
//
// Models the IMS (IP Multimedia Subsystem) security association negotiated during
// SIP REGISTER. After the first unprotected register, subsequent messages may need
// IPsec (IP Security) or TLS (Transport Layer Security) protection per 3GPP specs.

/// Parsed Security-Server / Security-Client header values from REGISTER negotiation.
public struct SecurityAssociation: Sendable, Equatable {
    public let mechanism: SecurityMechanism
    /// Raw Security-Server header value from the network.
    public let serverValue: String
    /// Raw Security-Client header value sent by the UE (User Equipment).
    public let verifyValue: String
    /// True once the security handshake is complete.
    public let isEstablished: Bool

    /// Creates a snapshot of the negotiated security association.
    public init(mechanism: SecurityMechanism, serverValue: String, verifyValue: String, isEstablished: Bool) {
        self.mechanism = mechanism
        self.serverValue = serverValue
        self.verifyValue = verifyValue
        self.isEstablished = isEstablished
    }
}

/// Rules for when SIP messages must be sent over a protected channel.
public enum SecurityPolicy {
    /// IPsec-protected messages are required after the initial REGISTER (not on first attempt).
    public static func requiresProtection(mechanism: SecurityMechanism, isInitialRegister: Bool) -> Bool {
        if isInitialRegister { return false }
        return mechanism == .ipsec3gpp
    }

    /// Throws if a protected register is attempted without a Security-Verify header.
    public static func assertProtected(mechanism: SecurityMechanism, isInitialRegister: Bool, hasSecurityVerify: Bool) throws {
        guard requiresProtection(mechanism: mechanism, isInitialRegister: isInitialRegister) else { return }
        guard hasSecurityVerify else {
            throw RegistrationError.securityRequired
        }
    }
}
