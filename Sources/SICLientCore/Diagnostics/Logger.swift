import Foundation

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

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct CorrelationID: Sendable, Hashable, Codable {
    public let value: String

    public init(prefix: String = "run") {
        self.value = "\(prefix)-\(UUID().uuidString.lowercased())"
    }

    public init(value: String) {
        self.value = value
    }
}

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

public struct Logger: Sendable {
    public let correlationID: CorrelationID
  private let minimumLevel: LogLevel
  private let output: @Sendable (String) -> Void
  private let encoder: JSONEncoder

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

    public func trace(_ message: String, fields: [String: String] = [:]) {
        log(.trace, message, fields: fields)
    }

    public func debug(_ message: String, fields: [String: String] = [:]) {
        log(.debug, message, fields: fields)
    }

    public func info(_ message: String, fields: [String: String] = [:]) {
        log(.info, message, fields: fields)
    }

    public func warn(_ message: String, fields: [String: String] = [:]) {
        log(.warn, message, fields: fields)
    }

    public func error(_ message: String, fields: [String: String] = [:]) {
        log(.error, message, fields: fields)
    }
}
