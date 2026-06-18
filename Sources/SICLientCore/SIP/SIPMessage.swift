import Foundation

public struct SIPHeader: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct SIPHeaders: Sendable, Equatable {
    private var entries: [SIPHeader]

    public init(entries: [SIPHeader] = []) {
        self.entries = entries
    }

    public var all: [SIPHeader] { entries }

    public subscript(_ name: String) -> String? {
        first(name)?.value
    }

    public func first(_ name: String) -> SIPHeader? {
        entries.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func allValues(_ name: String) -> [String] {
        entries.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    public mutating func set(_ name: String, value: String) {
        entries.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        entries.append(SIPHeader(name: name, value: value))
    }

    public mutating func append(_ name: String, value: String) {
        entries.append(SIPHeader(name: name, value: value))
    }

    public mutating func remove(_ name: String) {
        entries.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public struct SIPRequest: Sendable, Equatable {
    public var method: String
    public var requestURI: String
    public var version: String
    public var headers: SIPHeaders
    public var body: Data?

    public init(method: String, requestURI: String, version: String = "SIP/2.0", headers: SIPHeaders = SIPHeaders(), body: Data? = nil) {
        self.method = method
        self.requestURI = requestURI
        self.version = version
        self.headers = headers
        self.body = body
    }
}

public struct SIPResponse: Sendable, Equatable {
    public var version: String
    public var statusCode: Int
    public var reasonPhrase: String
    public var headers: SIPHeaders
    public var body: Data?

    public init(version: String = "SIP/2.0", statusCode: Int, reasonPhrase: String, headers: SIPHeaders = SIPHeaders(), body: Data? = nil) {
        self.version = version
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
        self.body = body
    }
}

public enum SIPMessage: Sendable, Equatable {
    case request(SIPRequest)
    case response(SIPResponse)

    public var headers: SIPHeaders {
        switch self {
        case .request(let request): request.headers
        case .response(let response): response.headers
        }
    }

    public var body: Data? {
        switch self {
        case .request(let request): request.body
        case .response(let response): response.body
        }
    }
}

public enum SIPParserError: Error, Sendable, CustomStringConvertible {
    case emptyInput
    case invalidStartLine(String)
    case missingHeaderSeparator
    case invalidContentLength
    case bodyTruncated

    public var description: String {
        switch self {
        case .emptyInput: return "Empty SIP message"
        case .invalidStartLine(let line): return "Invalid SIP start line: \(line)"
        case .missingHeaderSeparator: return "Missing CRLF separator between headers and body"
        case .invalidContentLength: return "Invalid Content-Length header"
        case .bodyTruncated: return "SIP body shorter than Content-Length"
        }
    }
}

public enum SIPParser {
    public static func parse(_ data: Data) throws -> SIPMessage {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw SIPParserError.emptyInput
        }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> SIPMessage {
        let normalized = text.hasSuffix("\r\n") ? text : text + "\r\n"
        guard let headerEnd = normalized.range(of: "\r\n\r\n") else {
            throw SIPParserError.missingHeaderSeparator
        }

        let headerBlock = String(normalized[..<headerEnd.lowerBound])
        let bodyStart = headerEnd.upperBound
        let lines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let startLine = lines.first else { throw SIPParserError.emptyInput }

        var headers = SIPHeaders()
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers.append(name, value: value)
        }

        let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0
        let bodyBytes = Array(normalized.utf8.dropFirst(normalized.distance(from: normalized.startIndex, to: bodyStart)))
        let bodyData: Data?
        if contentLength > 0 {
            guard bodyBytes.count >= contentLength else { throw SIPParserError.bodyTruncated }
            bodyData = Data(bodyBytes.prefix(contentLength))
        } else {
            let trimmed = String(decoding: bodyBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            bodyData = trimmed.isEmpty ? nil : Data(trimmed.utf8)
        }

        if startLine.hasPrefix("SIP/") {
            let parts = startLine.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3, let code = Int(parts[1]) else {
                throw SIPParserError.invalidStartLine(startLine)
            }
            return .response(SIPResponse(version: parts[0], statusCode: code, reasonPhrase: parts[2], headers: headers, body: bodyData))
        }

        let parts = startLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { throw SIPParserError.invalidStartLine(startLine) }
        return .request(SIPRequest(method: parts[0], requestURI: parts[1], version: parts[2], headers: headers, body: bodyData))
    }
}

public enum SIPSerializer {
    public static func serialize(_ message: SIPMessage) -> Data {
        Data(serializeString(message).utf8)
    }

    public static func serializeString(_ message: SIPMessage) -> String {
        switch message {
        case .request(let request):
            var lines = ["\(request.method) \(request.requestURI) \(request.version)"]
            lines.append(contentsOf: request.headers.all.map { "\($0.name): \($0.value)" })
            if let body = request.body, !body.isEmpty {
                lines.append("Content-Length: \(body.count)")
                let payload = String(decoding: body, as: UTF8.self)
                return lines.joined(separator: "\r\n") + "\r\n\r\n" + payload
            }
            lines.append("Content-Length: 0")
            return lines.joined(separator: "\r\n") + "\r\n\r\n"

        case .response(let response):
            var lines = ["\(response.version) \(response.statusCode) \(response.reasonPhrase)"]
            lines.append(contentsOf: response.headers.all.map { "\($0.name): \($0.value)" })
            if let body = response.body, !body.isEmpty {
                lines.append("Content-Length: \(body.count)")
                let payload = String(decoding: body, as: UTF8.self)
                return lines.joined(separator: "\r\n") + "\r\n\r\n" + payload
            }
            lines.append("Content-Length: 0")
            return lines.joined(separator: "\r\n") + "\r\n\r\n"
        }
    }
}
