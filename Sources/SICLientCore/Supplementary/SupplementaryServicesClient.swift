import Foundation

public struct CallForwardingRule: Sendable, Equatable {
    public var active: Bool
    public var target: String?

    public init(active: Bool = false, target: String? = nil) {
        self.active = active
        self.target = target
    }
}

public enum CallForwardingDocument {
    public static func parse(_ xml: String) -> CallForwardingRule {
        let active = xml.localizedCaseInsensitiveContains("active=\"true\"")
            || xml.localizedCaseInsensitiveContains("<active>true</active>")
        let target = extractTag("target", from: xml) ?? extractTag("cfu-uri", from: xml)
        return CallForwardingRule(active: active, target: target)
    }

    public static func serialize(rule: CallForwardingRule) -> String {
        let target = rule.target ?? ""
        let active = rule.active ? "true" : "false"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <communication-diversion xmlns="urn:3gpp:ns:extReg:1.0" active="\(active)">
          <rule id="cfu">
            <target>\(target)</target>
          </rule>
        </communication-diversion>
        """
    }

    private static func extractTag(_ name: String, from xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>"),
              let close = xml.range(of: "</\(name)>") else { return nil }
        return String(xml[open.upperBound ..< close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum XCAPError: Error, Sendable, CustomStringConvertible {
    case disabled
    case requestFailed(Int)
    case invalidDocument

    public var description: String {
        switch self {
        case .disabled: return "Supplementary services disabled in profile"
        case .requestFailed(let code): return "XCAP request failed: \(code)"
        case .invalidDocument: return "Invalid XCAP document"
        }
    }
}

public protocol XCAPTransport: Sendable {
    func get(url: URL) async throws -> (statusCode: Int, body: String)
    func put(url: URL, body: String, contentType: String) async throws -> Int
}

public struct URLSessionXCAPTransport: XCAPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(url: URL) async throws -> (statusCode: Int, body: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.3gpp.mmtel-config+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, String(decoding: data, as: UTF8.self))
    }

    public func put(url: URL, body: String, contentType: String) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = Data(body.utf8)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}

public actor InMemoryXCAPTransport: XCAPTransport {
    private var documents: [String: String] = [:]

    public init(seed: [String: String] = [:]) {
        self.documents = seed
    }

    public func get(url: URL) async throws -> (statusCode: Int, body: String) {
        if let body = documents[url.absoluteString] {
            return (200, body)
        }
        return (404, "")
    }

    public func put(url: URL, body: String, contentType: String) async throws -> Int {
        _ = contentType
        documents[url.absoluteString] = body
        return 200
    }
}

public actor SupplementaryServicesClient {
    private let profile: OperatorProfile
    private let transport: any XCAPTransport
    private let logger: Logger

    public init(profile: OperatorProfile, transport: any XCAPTransport, logger: Logger) {
        self.profile = profile
        self.transport = transport
        self.logger = logger
    }

    public func callForwardingUnconditionalURL(impu: String) -> URL? {
        guard profile.services.supplementary.enabled else { return nil }
        let encoded = impu.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? impu
        return URL(string: "\(profile.services.supplementary.xcapRootURI)/\(profile.services.supplementary.auid)/users/\(encoded)/servinfo.xml")
    }

    public func fetchCallForwarding(impu: String) async throws -> CallForwardingRule {
        guard profile.services.supplementary.enabled else { throw XCAPError.disabled }
        guard let url = callForwardingUnconditionalURL(impu: impu) else { throw XCAPError.invalidDocument }
        let (status, body) = try await transport.get(url: url)
        guard (200 ... 299).contains(status) else { throw XCAPError.requestFailed(status) }
        return CallForwardingDocument.parse(body)
    }

    public func setCallForwarding(impu: String, rule: CallForwardingRule) async throws {
        guard profile.services.supplementary.enabled else { throw XCAPError.disabled }
        guard let url = callForwardingUnconditionalURL(impu: impu) else { throw XCAPError.invalidDocument }
        let body = CallForwardingDocument.serialize(rule: rule)
        let status = try await transport.put(
            url: url,
            body: body,
            contentType: "application/vnd.3gpp.mmtel-config+xml"
        )
        guard (200 ... 299).contains(status) else { throw XCAPError.requestFailed(status) }
        logger.info("Call forwarding updated", fields: ["active": String(rule.active), "target": rule.target ?? ""])
    }
}
