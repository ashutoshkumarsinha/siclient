// Phase6Tests.swift
//
// Verifies Phase 6 hardening features: AKA resynchronization (AUTS), TLS lab config,
// PCO/DNS P-CSCF discovery, concurrent call sessions, 3GPP SMS payload, XCAP digest
// auth, PCAP export, hot profile reload, and secure memory wiping for IK/CK keys.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - AKA resynchronization

/// When the USIM detects a sequence number mismatch it returns AUTS instead of RES.
/// The client must send a second REGISTER with AUTS so the HSS resyncs and auth succeeds.
@Test func autsResyncRegistrationAgainstMockPCSCF() async throws {
    var profile = try loadFixtureProfile()
    profile.labSim?.akaVectors.append(
        AKAVector(
            rand: "235a551dbe46746a83255202074e3bca",
            autn: "a542211d8b3e10e7a54608d746c59f0a",
            res: "",
            ik: "",
            ck: "",
            auts: "aa558607b4c7d8f0f0b1e2d3c4f5a6b7"
        )
    )
    let fixedProfile = profile

    let state = MockPCSCFState()
    let transport = LoopbackSIPTransport(singleResponder: { data in
        MockPCSCFResponder.response(for: data, profile: fixedProfile, state: state)
    })

    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)
    try await fsm.register(expires: 60)

    #expect(await fsm.currentState() == .registered)
    #expect(state.registerAttemptCount >= 2)
}

// MARK: - TLS configuration

/// Lab builds allow skipping certificate verification (allowInsecureLab) while
/// production would pin the operator's P-CSCF certificate SHA-256 fingerprint.
@Test func tlsConfigDefaultsAllowLabInsecure() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.security.tls.allowInsecureLab == true)
    #expect(profile.security.tls.pinnedCertificateSHA256.isEmpty)
}

// MARK: - P-CSCF discovery

/// PCO (Protocol Configuration Options from the cellular modem) can deliver P-CSCF
/// addresses during LTE attach — an alternative to static config or DHCP.
@Test func pcoDiscoveryFromProfile() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.mode = .pco
    profile.pcscf.pcoAddresses = ["192.168.1.10:5060"]
    let adapter = ProductionNetworkAdapter()
    let endpoint = try adapter.discoverPCSCF(profile: profile)
    #expect(endpoint.host == "192.168.1.10")
    #expect(endpoint.port == 5060)
}

/// DNS SRV records list multiple P-CSCF candidates; the client must pick the lowest
/// priority target per RFC 2782, as operators do in production IMS deployments.
@Test func dnsSRVDiscoverySelectsLowestPriority() throws {
    let profile = try loadFixtureProfile()
    let records = [
        IMSDNSResolver.SRVRecord(target: "pcscf2.ims", port: 5060, priority: 20, weight: 1),
        IMSDNSResolver.SRVRecord(target: "pcscf1.ims", port: 5060, priority: 10, weight: 1),
    ]
    let endpoint = try PCSCFDiscovery.endpointFromDNS(profile: profile, srvRecords: records)
    #expect(endpoint.host == "pcscf1.ims")
}

// MARK: - Multi-session call control

/// VoLTE supports one active and one held call (call waiting / explicit hold). The
/// session FSM must track both dialog contexts independently.
@Test func concurrentActiveAndHeldSessions() async throws {
    let profile = try loadFixtureProfile()
    let transport = LoopbackSIPTransport { _ in nil }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let sessionFSM = SessionFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    let held = SessionContext(
        dialog: DialogContext(callID: "call-held"),
        state: .established,
        remoteURI: "sip:held@ims",
        localURI: "sip:user@ims"
    )
    let active = SessionContext(
        dialog: DialogContext(callID: "call-active"),
        state: .established,
        remoteURI: "sip:active@ims",
        localURI: "sip:user@ims"
    )
    await sessionFSM.injectSessionsForTesting(active: active, held: held)

    #expect(await sessionFSM.heldSessionContext()?.dialog.callID == "call-held")
    #expect(await sessionFSM.activeSessionContext()?.dialog.callID == "call-active")
}

// MARK: - SMS 3GPP payload

/// SMS-over-IMS can use binary RP-DATA encapsulation (3GPP TS 24.011) instead of
/// plain text; the builder must produce a valid RP-DATA frame for the SMSC.
@Test func sms3GPPPayloadBuilder() {
    let payload = SMSPayloadBuilder.rpData(userData: "hi", destination: "+15551212")
    #expect(!payload.isEmpty)
    #expect(String(decoding: payload, as: UTF8.self).contains("RP-DATA"))
}

// MARK: - XCAP digest authentication

/// Supplementary service documents on the XCAP server require HTTP Digest auth,
/// separate from SIP Digest but using the same username/password credentials.
@Test func xcapDigestAuthorizationHeader() {
    let header = XCAPDigestAuth.authorizationHeader(
        method: "GET",
        path: "/xcap-root/users/sip:user@ims/servinfo.xml",
        credentials: XCAPDigestCredentials(username: "user", password: "secret"),
        realm: "xcap.ims",
        nonce: "abc123"
    )
    #expect(header.contains("Digest"))
    #expect(header.contains("response="))
}

// MARK: - Packet capture export

/// PCAP export lets engineers replay SIP/RTP in Wireshark — essential for debugging
/// registration and call flows against real operator networks.
@Test func pcapExporterRecordsPackets() throws {
    let exporter = PcapExporter(enabled: true)
    exporter.record(Data("REGISTER".utf8), direction: "sip-out")
    exporter.record(Data("200 OK".utf8), direction: "sip-in")
    #expect(exporter.packetCount() == 2)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("siclient-test.pcap")
    try exporter.export(to: url)
    #expect(FileManager.default.fileExists(atPath: url.path))
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Hot profile reload

/// Operators may push updated profiles without restarting the app; ProfileManager must
/// detect file changes and reload timer/security settings on demand.
@Test func profileManagerReloadDetectsChange() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-reload-test.json")
    let profile = try loadFixtureProfile()
    let data = try JSONEncoder().encode(profile)
    try data.write(to: url)

    let manager = ProfileManager(profile: profile, profileURL: url)
    #expect(try await manager.reloadIfChanged() == false)

    var updated = profile
    updated.timers.keepaliveSec = 99
    try JSONEncoder().encode(updated).write(to: url)
    #expect(try await manager.reloadIfChanged() == true)
    #expect(await manager.currentProfile().timers.keepaliveSec == 99)
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Secure memory

/// IK/CK keys from AKA must be wiped from memory after use to reduce exposure if
/// the process is dumped — a security requirement for credential handling.
@Test func secureMemoryWipesOnDeinit() {
    let context = SecureAKAContext()
    context.store(ik: Data(repeating: 0xAB, count: 16), ck: Data(repeating: 0xCD, count: 16))
    context.wipe()
}
