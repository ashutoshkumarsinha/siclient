import Foundation
import CommonCrypto

public struct XCAPDigestCredentials: Sendable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public enum XCAPDigestAuth {
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
        // codeql[swift/weak-cryptography]: HTTP Digest (RFC 2617) requires MD5 for XCAP auth headers.
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

public struct DigestXCAPTransport: XCAPTransport {
    private let inner: any XCAPTransport
    private let credentials: XCAPDigestCredentials
    private let realm: String

    public init(wrapping inner: any XCAPTransport, credentials: XCAPDigestCredentials, realm: String? = nil) {
        self.inner = inner
        self.credentials = credentials
        self.realm = realm ?? "xcap"
    }

    public func get(url: URL) async throws -> (statusCode: Int, body: String) {
        _ = XCAPDigestAuth.authorizationHeader(method: "GET", path: url.path, credentials: credentials, realm: realm)
        return try await inner.get(url: url)
    }

    public func put(url: URL, body: String, contentType: String) async throws -> Int {
        _ = XCAPDigestAuth.authorizationHeader(method: "PUT", path: url.path, credentials: credentials, realm: realm)
        return try await inner.put(url: url, body: body, contentType: contentType)
    }
}
