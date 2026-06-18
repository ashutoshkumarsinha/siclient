import Foundation

public enum NetworkResiliencePolicy: Sendable {
    public static func shouldReregisterAfterIPChange(previousPath: String, currentPath: String) -> Bool {
        previousPath != currentPath && !currentPath.isEmpty
    }

    public static func shouldReregisterAfterIPChange(previousIP: String, currentIP: String) -> Bool {
        previousIP != currentIP && !currentIP.isEmpty
    }

    public static func pathLabel(for accessInfo: AccessInfo) -> String {
        "\(accessInfo.rat.rawValue):\(accessInfo.cellOrAPIdentifier)"
    }

    public static func registrationRetryDelay(attempt: Int) -> Duration {
        let capped = min(attempt, 5)
        return .milliseconds(500 * (1 << capped))
    }

    public static func networkRecoveryDeadline(timeoutSec: Int) -> ContinuousClock.Instant {
        ContinuousClock.now + .seconds(timeoutSec)
    }
}
