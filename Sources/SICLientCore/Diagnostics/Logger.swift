import Foundation

// MARK: - File Overview
// Structured JSON logging with correlation IDs for tracing one client run end-to-end.
// Redacts sensitive authentication material before anything is printed.

/// Severity levels for log messages, from most verbose to most severe.
public enum LogLevel: String, Codable, Sendable, Comparable {
    case trace
    case debug
    case info
    case warn
    case error

    private var rank: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warn: return 3
        case .error: return 4
        }
    }

    /// Compares log levels by severity rank.
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Unique ID that ties all log lines from one client session together.
public struct CorrelationID: Sendable, Hashable, Codable {
    public let value: String

    /// Creates a new random correlation ID with an optional prefix.
    public init(prefix: String = "run") {
        self.value = "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    /// Creates a correlation ID from an existing string value.
    public init(value: String) {
        self.value = value
    }
}

/// One JSON log line with timestamp, level, correlation ID, message, and extra fields.
public struct LogEntry: Codable, Sendable {
    public let timestamp: String
    public let level: LogLevel
    public let correlationID: String
    public let message: String
    public let fields: [String: String]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case level
        case correlationID = "correlation_id"
        case message
        case fields
    }
}

/// Emits structured JSON log lines, filtering by minimum level and redacting secrets.
public struct Logger: Sendable {
    public let correlationID: CorrelationID
  private let minimumLevel: LogLevel
  private let output: @Sendable (String) -> Void
  private let encoder: JSONEncoder

    /// Creates a logger with correlation ID, minimum level, and output handler.
    public init(
        correlationID: CorrelationID = CorrelationID(),
        minimumLevel: LogLevel = .info,
        output: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.correlationID = correlationID
        self.minimumLevel = minimumLevel
        self.output = output
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    /// Writes a log entry at the given level if it meets the minimum threshold.
    public func log(
        _ level: LogLevel,
        _ message: String,
        fields: [String: String] = [:]
    ) {
        guard level >= minimumLevel else { return }

        let sanitizedMessage = SecretRedactor.redact(message)
        let redactedFields = Dictionary(
            fields.map { key, value in
                (key, SecretRedactor.redactField(key: key, value: value))
            },
            uniquingKeysWith: { _, rhs in rhs }
        )

        let entry = LogEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            level: level,
            correlationID: correlationID.value,
            message: sanitizedMessage,
            fields: redactedFields
        )

        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else {
            return
        }

        output(line)
    }

    /// Logs at trace level.
    public func trace(_ message: String, fields: [String: String] = [:]) {
        log(.trace, message, fields: fields)
    }

    /// Logs at debug level.
    public func debug(_ message: String, fields: [String: String] = [:]) {
        log(.debug, message, fields: fields)
    }

    /// Logs at info level.
    public func info(_ message: String, fields: [String: String] = [:]) {
        log(.info, message, fields: fields)
    }

    /// Logs at warn level.
    public func warn(_ message: String, fields: [String: String] = [:]) {
        log(.warn, message, fields: fields)
    }

    /// Logs at error level.
    public func error(_ message: String, fields: [String: String] = [:]) {
        log(.error, message, fields: fields)
    }
}
