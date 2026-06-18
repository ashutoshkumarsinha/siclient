import Foundation

// MARK: - File Overview
// Tracks how long key operations take (registration, call setup) and compares them
// against lab performance targets.

/// Measured durations for registration and call setup in milliseconds.
public struct PerformanceMetrics: Sendable, Equatable {
    public var registrationDurationMs: Double?
    public var callSetupDurationMs: Double?

    /// Creates performance metrics with optional duration values.
    public init(registrationDurationMs: Double? = nil, callSetupDurationMs: Double? = nil) {
        self.registrationDurationMs = registrationDurationMs
        self.callSetupDurationMs = callSetupDurationMs
    }
}

/// Lab target thresholds and pass/fail checks for performance metrics.
public enum PerformanceBenchmarks {
    /// Maximum acceptable IMS registration time in milliseconds.
    public static let registrationTargetMs: Double = 2000
    /// Maximum acceptable call setup time in milliseconds.
    public static let callSetupTargetMs: Double = 3000

    /// True when registration completed faster than the target.
    public static func meetsRegistrationTarget(_ durationMs: Double) -> Bool {
        durationMs < registrationTargetMs
    }

    /// True when call setup completed faster than the target.
    public static func meetsCallSetupTarget(_ durationMs: Double) -> Bool {
        durationMs < callSetupTargetMs
    }
}

/// Utility for measuring how long an async operation takes.
public enum PerformanceTimer {
    /// Runs an async operation and returns its duration in milliseconds.
    public static func measureMilliseconds(_ operation: () async throws -> Void) async rethrows -> Double {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start) * 1000
    }
}
