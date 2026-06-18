import Foundation

public enum SIPErrorAction: Sendable, Equatable {
    case retry(maxAttempts: Int)
    case reauthenticate
    case stop
    case cleanupDialog
    case ignore
}

public enum SIPErrorMapper {
    public static func action(for statusCode: Int, method: String? = nil) -> SIPErrorAction {
        switch statusCode {
        case 401:
            return .reauthenticate
        case 403:
            return .stop
        case 408:
            return .retry(maxAttempts: 3)
        case 480, 486, 487, 488, 600, 603:
            return .cleanupDialog
        case 503:
            return .retry(maxAttempts: 2)
        default:
            if let method, method == SIPMethod.invite.rawValue, (500 ... 599).contains(statusCode) {
                return .cleanupDialog
            }
            return .ignore
        }
    }
}
