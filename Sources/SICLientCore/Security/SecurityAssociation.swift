import Foundation

public struct SecurityAssociation: Sendable, Equatable {
    public let mechanism: SecurityMechanism
    public let serverValue: String
    public let verifyValue: String
    public let isEstablished: Bool

    public init(mechanism: SecurityMechanism, serverValue: String, verifyValue: String, isEstablished: Bool) {
        self.mechanism = mechanism
        self.serverValue = serverValue
        self.verifyValue = verifyValue
        self.isEstablished = isEstablished
    }
}

public enum SecurityPolicy {
    public static func requiresProtection(mechanism: SecurityMechanism, isInitialRegister: Bool) -> Bool {
        if isInitialRegister { return false }
        return mechanism == .ipsec3gpp
    }

    public static func assertProtected(mechanism: SecurityMechanism, isInitialRegister: Bool, hasSecurityVerify: Bool) throws {
        guard requiresProtection(mechanism: mechanism, isInitialRegister: isInitialRegister) else { return }
        guard hasSecurityVerify else {
            throw RegistrationError.securityRequired
        }
    }
}
