import Foundation

// MARK: - File overview
//
// Network resilience settings for the IMS (IP Multimedia Subsystem) client: MTU
// (Maximum Transmission Unit) limits for SIP (Session Initiation Protocol) over UDP,
// registration retry counts, and network recovery timeouts.

/// Controls how the client retries registration and recovers from network loss.
public struct ResilienceConfig: Codable, Sendable, Equatable {
    /// Max SIP message size over UDP before switching to TCP/TLS fallback (bytes).
    public var mtuBytes: Int
    /// How many times to retry SIP REGISTER on transient failure.
    public var maxRegistrationRetries: Int
    /// Seconds to wait for network recovery before giving up.
    public var networkRecoveryTimeoutSec: Int

    enum CodingKeys: String, CodingKey {
        case mtuBytes = "mtu_bytes"
        case maxRegistrationRetries = "max_registration_retries"
        case networkRecoveryTimeoutSec = "network_recovery_timeout_sec"
    }

    /// Creates resilience settings with typical mobile-network defaults.
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
