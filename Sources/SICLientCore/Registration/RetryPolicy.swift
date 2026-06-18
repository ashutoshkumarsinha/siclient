import Foundation

// MARK: - File Overview
//
// When registration or SIP transactions fail, this policy decides whether to retry
// and how long to wait. It delegates status-code decisions to SIPErrorMapper and
// uses exponential backoff from NetworkResiliencePolicy.

/// Retry rules for failed IMS registration attempts.
public enum RetryPolicy {
    /// Returns true if another registration attempt should be made.
    public static func shouldRetryRegistration(
        statusCode: Int?,
        error: Error?,
        attempt: Int,
        maxAttempts: Int
    ) -> Bool {
        guard attempt < maxAttempts else { return false }
        if let statusCode {
            switch SIPErrorMapper.action(for: statusCode, method: SIPMethod.register.rawValue) {
            case .retry:
                return true
            case .reauthenticate, .stop, .cleanupDialog, .ignore:
                return false
            }
        }
        // Transport-level timeouts are always worth retrying.
        if error is ClientTransactionError {
            return true
        }
        return false
    }

    /// Computes backoff delay before the next registration retry.
    public static func delayBeforeRetry(attempt: Int) -> Duration {
        NetworkResiliencePolicy.registrationRetryDelay(attempt: attempt)
    }

    /// Parses Retry-After header from a SIP error response, if present.
    public static func retryAfterHeader(from response: SIPResponse) -> Duration? {
        guard let value = response.headers["Retry-After"] else { return nil }
        if let seconds = Int(value.trimmingCharacters(in: .whitespaces)) {
            return .seconds(seconds)
        }
        return nil
    }
}
