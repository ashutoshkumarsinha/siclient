// SIPTests.swift
//
// Verifies low-level SIP message parsing, serialization, Digest challenge parsing,
// and REGISTER request construction. SIP is the signaling protocol IMS uses for
// registration, calls, SMS, and supplementary services — these tests cover the wire format.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Parser & serializer

/// A well-formed REGISTER must parse and re-serialize without losing the method or
/// Request-URI — garbled SIP would fail at the P-CSCF before any IMS logic runs.
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

/// SIP requires CRLF-separated headers ending with a blank line; malformed messages
/// must be rejected rather than partially parsed.
@Test func rejectsMissingHeaderTerminator() {
    let raw = "REGISTER sip:example.org SIP/2.0\r\nVia: SIP/2.0/UDP 1.1.1.1"
    #expect(throws: SIPParserError.self) {
        _ = try SIPParser.parse(raw)
    }
}

// MARK: - Digest authentication

/// The P-CSCF returns a 401 with a Digest challenge (realm, nonce, AUTN for AKA).
/// The client must parse algorithm=AKAv1-MD5 and extract AUTN for the SIM.
@Test func parsesDigestChallenge() throws {
    let header = #"Digest realm="ims.example.org", nonce="I1pVHb5kdGaoUlUgd058yg==", algorithm=AKAv1-MD5, qop="auth", autn="a542211d8b3e10e7a54608d746c59f0a""#
    let challenge = try #require(DigestAuthParser.parseChallenge(header))
    #expect(challenge.realm == "ims.example.org")
    #expect(challenge.algorithm == "AKAv1-MD5")
}

// MARK: - IMS REGISTER construction

/// Initial REGISTER must include 3GPP-mandatory headers: PANI, mmtel service tag,
/// Security-Client, and Supported extensions. Missing headers cause P-CSCF rejection.
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
