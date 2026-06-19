import Foundation
import CryptoKit

// MARK: - File Overview
// HTTP Digest authentication for XCAP (XML Configuration Access Protocol) requests.
// XCAP is used to read and write supplementary service settings (e.g. call forwarding)
// stored as XML documents on the operator's server.

/// Username and password used for XCAP HTTP Digest authentication.
public struct XCAPDigestCredentials: Sendable, Equatable {
    public var username: String
    public var password: String

    /// Creates digest credentials for XCAP requests.
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Computes HTTP Digest Authorization headers for XCAP GET/PUT requests.
public enum XCAPDigestAuth {
    /// Builds a Digest Authorization header value for the given method and path.
    public static func authorizationHeader(
        method: String,
        path: String,
        credentials: XCAPDigestCredentials,
        realm: String,
        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) -> String {
        let ha1 = md5("\(credentials.username):\(realm):\(credentials.password)")
        let ha2 = md5("\(method):\(path)")
        let response = md5("\(ha1):\(nonce):\(ha2)")
        return #"Digest username="\#(credentials.username)", realm="\#(realm)", nonce="\#(nonce)", uri="\#(path)", response="\#(response)""#
    }

    private static func md5(_ input: String) -> String {
        // HTTP Digest (RFC 2617) requires MD5 for XCAP auth headers — not a general-purpose hash choice.
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// XCAP transport wrapper that attaches Digest auth headers (header is computed but not yet sent).
public struct DigestXCAPTransport: XCAPTransport {
    private let inner: any XCAPTransport
    private let credentials: XCAPDigestCredentials
    private let realm: String

    /// Wraps an inner transport and stores digest credentials for auth header generation.
    public init(wrapping inner: any XCAPTransport, credentials: XCAPDigestCredentials, realm: String? = nil) {
        self.inner = inner
        self.credentials = credentials
        self.realm = realm ?? "xcap"
    }

    /// Performs a GET with digest auth header computed (lab: header not attached to request yet).
    public func get(url: URL) async throws -> (statusCode: Int, body: String) {
        _ = XCAPDigestAuth.authorizationHeader(method: "GET", path: url.path, credentials: credentials, realm: realm)
        return try await inner.get(url: url)
    }

    /// Performs a PUT with digest auth header computed (lab: header not attached to request yet).
    public func put(url: URL, body: String, contentType: String) async throws -> Int {
        _ = XCAPDigestAuth.authorizationHeader(method: "PUT", path: url.path, credentials: credentials, realm: realm)
        return try await inner.put(url: url, body: body, contentType: contentType)
    }
}
