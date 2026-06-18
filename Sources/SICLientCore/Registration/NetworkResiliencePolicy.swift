import Foundation

// MARK: - File Overview
//
// Decides when the client should re-register after network changes (Wi-Fi ↔ LTE,
// IP address change) and provides exponential backoff delays for retry attempts.

/// Rules for detecting network changes that require a new IMS registration.
public enum NetworkResiliencePolicy: Sendable {
    /// Returns true when the radio access path label changed (e.g. LTE → Wi-Fi).
    public static func shouldReregisterAfterIPChange(previousPath: String, currentPath: String) -> Bool {
        previousPath != currentPath && !currentPath.isEmpty
    }

    /// Returns true when the local IP address changed.
    public static func shouldReregisterAfterIPChange(previousIP: String, currentIP: String) -> Bool {
        previousIP != currentIP && !currentIP.isEmpty
    }

    /// Builds a stable label from RAT (Radio Access Type) and cell/AP identifier.
    public static func pathLabel(for accessInfo: AccessInfo) -> String {
        "\(accessInfo.rat.rawValue):\(accessInfo.cellOrAPIdentifier)"
    }

    /// Exponential backoff delay capped at ~16 seconds for registration retries.
    public static func registrationRetryDelay(attempt: Int) -> Duration {
        let capped = min(attempt, 5)
        return .milliseconds(500 * (1 << capped))
    }

    /// Deadline for background network-recovery re-registration attempts.
    public static func networkRecoveryDeadline(timeoutSec: Int) -> ContinuousClock.Instant {
        ContinuousClock.now + .seconds(timeoutSec)
    }
}
