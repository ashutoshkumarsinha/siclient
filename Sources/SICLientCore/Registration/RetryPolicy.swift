import Foundation

public enum RetryPolicy {
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
        if error is ClientTransactionError {
            return true
        }
        return false
    }

    public static func delayBeforeRetry(attempt: Int) -> Duration {
        NetworkResiliencePolicy.registrationRetryDelay(attempt: attempt)
    }

    public static func retryAfterHeader(from response: SIPResponse) -> Duration? {
        guard let value = response.headers["Retry-After"] else { return nil }
        if let seconds = Int(value.trimmingCharacters(in: .whitespaces)) {
            return .seconds(seconds)
        }
        return nil
    }
}
