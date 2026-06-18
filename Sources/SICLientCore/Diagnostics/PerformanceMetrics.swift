import Foundation

public struct PerformanceMetrics: Sendable, Equatable {
    public var registrationDurationMs: Double?
    public var callSetupDurationMs: Double?

    public init(registrationDurationMs: Double? = nil, callSetupDurationMs: Double? = nil) {
        self.registrationDurationMs = registrationDurationMs
        self.callSetupDurationMs = callSetupDurationMs
    }
}

public enum PerformanceBenchmarks {
    public static let registrationTargetMs: Double = 2000
    public static let callSetupTargetMs: Double = 3000

    public static func meetsRegistrationTarget(_ durationMs: Double) -> Bool {
        durationMs < registrationTargetMs
    }

    public static func meetsCallSetupTarget(_ durationMs: Double) -> Bool {
        durationMs < callSetupTargetMs
    }
}

public enum PerformanceTimer {
    public static func measureMilliseconds(_ operation: () async throws -> Void) async rethrows -> Double {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start) * 1000
    }
}
