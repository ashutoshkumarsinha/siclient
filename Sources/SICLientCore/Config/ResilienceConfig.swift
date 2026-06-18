import Foundation

public struct ResilienceConfig: Codable, Sendable, Equatable {
    public var mtuBytes: Int
    public var maxRegistrationRetries: Int
    public var networkRecoveryTimeoutSec: Int

    enum CodingKeys: String, CodingKey {
        case mtuBytes = "mtu_bytes"
        case maxRegistrationRetries = "max_registration_retries"
        case networkRecoveryTimeoutSec = "network_recovery_timeout_sec"
    }

    public init(
        mtuBytes: Int = 1300,
        maxRegistrationRetries: Int = 3,
        networkRecoveryTimeoutSec: Int = 30
    ) {
        self.mtuBytes = mtuBytes
        self.maxRegistrationRetries = maxRegistrationRetries
        self.networkRecoveryTimeoutSec = networkRecoveryTimeoutSec
    }
}
