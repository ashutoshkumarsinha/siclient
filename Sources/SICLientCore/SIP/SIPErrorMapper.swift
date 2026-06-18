import Foundation

// MARK: - File Overview
//
// When a SIP server returns an error status code (4xx/5xx), the client must decide
// what to do next: retry, re-authenticate, stop, or clean up a call dialog.
// This file maps common SIP response codes to those recovery actions.

/// Recovery action the client should take after a SIP error response.
public enum SIPErrorAction: Sendable, Equatable {
    /// Try the same request again, up to the given attempt limit.
    case retry(maxAttempts: Int)
    /// Send a new authenticated request (typically after HTTP-style 401 Unauthorized).
    case reauthenticate
    /// Stop and do not retry (permanent failure).
    case stop
    /// Tear down the SIP dialog (call session) associated with this transaction.
    case cleanupDialog
    /// No special handling required.
    case ignore
}

/// Maps SIP response status codes to recommended client recovery actions.
public enum SIPErrorMapper {
    /// Returns the action to take for a given SIP status code and optional request method.
    public static func action(for statusCode: Int, method: String? = nil) -> SIPErrorAction {
        switch statusCode {
        case 401:
            // 401 Unauthorized — credentials missing or stale; re-run IMS-AKA auth flow.
            return .reauthenticate
        case 403:
            return .stop
        case 408:
            // 408 Request Timeout — transient; safe to retry a few times.
            return .retry(maxAttempts: 3)
        case 480, 486, 487, 488, 600, 603:
            // Call-related failures — end the dialog rather than leaving it half-open.
            return .cleanupDialog
        case 503:
            // 503 Service Unavailable — server overloaded; brief retry may succeed.
            return .retry(maxAttempts: 2)
        default:
            // Server errors on INVITE should always clean up the half-established dialog.
            if let method, method == SIPMethod.invite.rawValue, (500 ... 599).contains(statusCode) {
                return .cleanupDialog
            }
            return .ignore
        }
    }
}
