import Foundation
import Testing
@testable import SICLientCore

@Test func parsesSIPRequestRoundTrip() throws {
    let raw = """
    REGISTER sip:ims.example.org SIP/2.0\r
    Via: SIP/2.0/UDP 10.0.0.2:5060;branch=z9hG4bK776\r
    Max-Forwards: 70\r
    From: <sip:user@ims.example.org>;tag=1928301774\r
    To: <sip:user@ims.example.org>\r
    Call-ID: a84b4e76@10.0.0.2\r
    CSeq: 1 REGISTER\r
    Contact: <sip:user@10.0.0.2:5060>\r
    Content-Length: 0\r
    \r

    """
    let message = try SIPParser.parse(raw)
    guard case .request(let request) = message else {
        Issue.record("Expected SIP request")
        return
    }
    #expect(request.method == "REGISTER")
    let serialized = SIPSerializer.serializeString(message)
    #expect(serialized.contains("REGISTER sip:ims.example.org SIP/2.0"))
}

@Test func rejectsMissingHeaderTerminator() {
    let raw = "REGISTER sip:example.org SIP/2.0\r\nVia: SIP/2.0/UDP 1.1.1.1"
    #expect(throws: SIPParserError.self) {
        _ = try SIPParser.parse(raw)
    }
}

@Test func parsesDigestChallenge() throws {
    let header = #"Digest realm="ims.example.org", nonce="I1pVHb5kdGaoUlUgd058yg==", algorithm=AKAv1-MD5, qop="auth", autn="a542211d8b3e10e7a54608d746c59f0a""#
    let challenge = try #require(DigestAuthParser.parseChallenge(header))
    #expect(challenge.realm == "ims.example.org")
    #expect(challenge.algorithm == "AKAv1-MD5")
}

@Test func buildsRegisterWithRequiredIMSHeaders() throws {
    let profile = try loadFixtureProfile()
    let context = RegistrationContext(callID: "test-call-id", cseq: 1)
    let request = RegisterRequestBuilder.makeRegister(
        profile: profile,
        impi: "user@ims.example.org",
        impu: "sip:user@ims.example.org",
        pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=123",
        localIP: "10.0.0.2",
        localPort: 5060,
        context: context
    )

    #expect(request.headers["P-Access-Network-Info"]?.contains("3GPP-E-UTRAN") == true)
    #expect(request.headers["P-Preferred-Service"]?.contains("mmtel") == true)
    #expect(request.headers["Security-Client"]?.contains("tls") == true)
    #expect(request.headers["Supported"]?.contains("path") == true)
}
