import Foundation

public enum NetworkResiliencePolicy: Sendable {
    public static func shouldReregisterAfterIPChange(previousPath: String, currentPath: String) -> Bool {
        previousPath != currentPath && !currentPath.isEmpty
    }

    public static func registrationRetryDelay(attempt: Int) -> Duration {
        let capped = min(attempt, 5)
        return .milliseconds(500 * (1 << capped))
    }
}
