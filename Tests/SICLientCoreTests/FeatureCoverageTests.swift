// FeatureCoverageTests.swift
//
// Broad integration tests spanning registration, security, discovery, emergency, SMS,
// supplementary services, call control, media, diagnostics, resilience, and handover.
// Each test maps to a real IMS feature a VoLTE UE must support for carrier certification.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Registration & Authentication

/// When AKA resync is needed the Digest Authorization header carries AUTS instead of
/// response — the P-CSCF forwards this to the HSS for sequence resynchronization.
@Test func digestCredentialsAUTSHeaderOmitsResponse() {
    let creds = DigestCredentials(
        username: "user@ims",
        realm: "ims.example",
        nonce: "abc123",
        uri: "sip:ims.example",
        response: "",
        auts: "AAbbCCdd=="
    )
    let header = creds.headerValue()
    #expect(header.contains("auts=\"AAbbCCdd==\""))
    #expect(!header.contains("response="))
}

/// The client must parse inbound Digest credentials that contain AUTS (from a prior
/// resync attempt) and recognize that no response digest is present yet.
@Test func parseDigestCredentialsWithAUTS() throws {
    let header = #"Digest username="user", realm="ims", nonce="n", uri="sip:ims", auts="abc123==""#
    let creds = try #require(DigestAuthParser.parseCredentials(header))
    #expect(creds.auts == "abc123==")
    #expect(creds.response.isEmpty)
}

/// IMS embeds RAND and AUTN inside the SIP Digest nonce; the decoder extracts them
/// for passing to the USIM AKA algorithm.
@Test func imsChallengeDecoderRandAndAUTN() throws {
    let randHex = "235a551dbe46746a83255202074e3bca"
    let randData = try #require(Data(hexString: randHex))
    let challenge = DigestChallenge(
        realm: "ims",
        nonce: randData.base64EncodedString(),
        autn: "a542211d8b3e10e7a54608d746c59f0a"
    )
    let (rand, autn) = try IMSChallengeDecoder.randAndAUTN(from: challenge)
    #expect(rand.hexLowercase == randHex)
    #expect(autn.hexLowercase == "a542211d8b3e10e7a54608d746c59f0a")
}

/// A lab SIM vector configured for sync failure must return AUTS, simulating what
/// happens when the USIM detects an out-of-sync SQN from the network.
@Test func labSimReturnsAUTSOnSyncFailureVector() throws {
    var config = try #require(try loadFixtureProfile().labSim)
    config.akaVectors = [
        AKAVector(
            rand: "235a551dbe46746a83255202074e3bca",
            autn: "a542211d8b3e10e7a54608d746c59f0a",
            res: "",
            ik: "",
            ck: "",
            auts: "aa558607b4c7d8f0f0b1e2d3c4f5a6b7"
        ),
    ]
    let adapter = LabSimAdapter(config: config)
    let rand = try #require(Data(hexString: "235a551dbe46746a83255202074e3bca"))
    let autn = try #require(Data(hexString: "a542211d8b3e10e7a54608d746c59f0a"))
    let result = try adapter.akaChallenge(rand: rand, autn: autn)
    guard case .syncFailure(let auts) = result.status else {
        Issue.record("Expected sync failure")
        return
    }
    #expect(auts.hexLowercase == "aa558607b4c7d8f0f0b1e2d3c4f5a6b7")
}

/// Lab profiles with lab_sim config must instantiate LabSimAdapter and expose IMPI
/// for SIP private identity in REGISTER requests.
@Test func simAdapterFactorySelectsLabSim() throws {
    let profile = try loadFixtureProfile()
    let adapter = SimAdapterFactory.make(profile: profile)
    let impi = try adapter.getIMPI()
    #expect(impi.contains("001010123456789"))
}

/// Production profiles without lab credentials must fail when requesting IMPI,
/// preventing accidental registration without a real USIM or credential store.
@Test func simAdapterFactoryUnavailableWithoutLabSim() {
    let profile = OperatorProfile(
        profileID: "prod",
        homeDomain: "ims.example.org",
        pcscf: PCSCFConfig(mode: .static, address: "10.0.0.1", port: 5060),
        transport: TransportConfig(preference: [.udp]),
        security: SecurityConfig(mechanism: .tls)
    )
    let adapter = SimAdapterFactory.make(profile: profile)
    #expect(throws: SimAdapterError.noCredentials) {
        _ = try adapter.getIMPI()
    }
}

/// 200 OK to REGISTER carries Security-Server, Service-Route, P-Associated-URI, and
/// Expires — all must be parsed into RegistrationContext for subsequent SIP routing.
@Test func registrationParserExtractsSecurityAssociation() throws {
    var headers = SIPHeaders()
    headers.set("Security-Server", value: "tls; port=5061")
    headers.set("Service-Route", value: "<sip:pcscf.example;lr>")
    headers.set("P-Associated-URI", value: "<sip:user@example>")
    headers.set("Expires", value: "3600")
    let response = SIPResponse(statusCode: 200, reasonPhrase: "OK", headers: headers)
    let profile = try loadFixtureProfile()
    let context = RegistrationResponseParser.parse200OK(response, profile: profile)
    #expect(context.securityAssociation?.isEstablished == true)
    #expect(context.serviceRoute?.contains("pcscf") == true)
}

// MARK: - Security

/// 3GPP IMS mandates IPSec for signaling after initial registration; the client must
/// refuse to proceed without Security-Verify when ipsec3gpp is configured.
@Test func securityPolicyRequiresVerifyForIPSec() {
    #expect(SecurityPolicy.requiresProtection(mechanism: .ipsec3gpp, isInitialRegister: false))
    #expect(!SecurityPolicy.requiresProtection(mechanism: .tls, isInitialRegister: false))
    do {
        try SecurityPolicy.assertProtected(
            mechanism: .ipsec3gpp,
            isInitialRegister: false,
            hasSecurityVerify: false
        )
        Issue.record("Expected securityRequired")
    } catch RegistrationError.securityRequired {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

/// Lab TLS config allows skipping cert validation so developers can test against
/// self-signed P-CSCF certificates without pinning production roots.
@Test func tlsConfigLabInsecureAllowsBypass() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.security.tls.allowInsecureLab == true)
}

// MARK: - Discovery & Platform

/// DHCP-based P-CSCF discovery (used on some Wi-Fi IMS deployments) must parse
/// address:port pairs from the profile's dhcpAddresses list.
@Test func dhcpDiscoveryFromProfile() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.mode = .dhcp
    profile.pcscf.dhcpAddresses = ["10.20.30.40:5070"]
    let adapter = ProductionNetworkAdapter()
    let endpoint = try adapter.discoverPCSCF(profile: profile)
    #expect(endpoint.host == "10.20.30.40")
    #expect(endpoint.port == 5070)
}

/// DNS hostname resolution for P-CSCF FQDNs must map known hosts to IP addresses while
/// passing through unknown names unchanged for downstream resolver handling.
@Test func stubNetworkResolvesHostnameMap() throws {
    let adapter = StubNetworkAdapter(resolvedHosts: ["pcscf.ims": ["10.0.0.99"]])
    #expect(try adapter.resolveHostname("pcscf.ims") == ["10.0.0.99"])
    #expect(try adapter.resolveHostname("unknown.example") == ["unknown.example"])
}

/// Profiles preferring UDP with TCP/TLS fallback must create a FallbackSIPTransport
/// so large SIP messages automatically switch to a reliable protocol.
@Test func transportFactoryCreatesFallbackForUDPProfile() throws {
    let profile = try loadFixtureProfile()
    let endpoint = PCSCFEndpoint(host: "10.0.0.1", port: 5060, transport: .udp)
    let transport = TransportFactory.make(endpoint: endpoint, profile: profile)
    #expect(transport is FallbackSIPTransport)
}

// MARK: - Configuration

/// Premium operator profiles advertise EVS as the preferred wideband codec for HD voice.
@Test func loadsPremiumEVSProfile() throws {
    let profile = try loadPremiumProfile()
    #expect(profile.codecs.audio.first == "EVS")
    #expect(profile.profileID.contains("evs") || profile.codecs.audio.contains("EVS"))
}

/// Operator profiles carry feature toggles (emergency, SMS, supplementary, eSRVCC),
/// media port, and resilience settings that drive runtime behavior.
@Test func profileServicesConfigRoundTrip() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.services.emergency.enabled)
    #expect(profile.services.sms.enabled)
    #expect(profile.services.supplementary.enabled)
    #expect(profile.services.handover.esrvccEnabled)
    #expect(profile.media.localRTPPort == 40_000)
    #expect(profile.resilience.maxRegistrationRetries == 3)
}

/// PCO discovery mode with explicit addresses must pass validation — carriers
/// provision these from the modem's attach response.
@Test func profileValidationAcceptsPCOAddresses() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.mode = .pco
    profile.pcscf.pcoAddresses = ["10.0.0.2:5060"]
    try ProfileValidator.validate(profile)
}

// MARK: - Emergency

/// Emergency INVITE to tel:112 must include Priority: emergency and P-Emergency-Info
/// so the IMS routes to the correct PSAP with appropriate QoS.
@Test func emergencyInviteIncludesPriorityHeaders() throws {
    var profile = try loadFixtureProfile()
    profile.services.emergency.enabled = true
    let invite = EmergencyRequestBuilder.makeEmergencyInvite(
        profile: profile,
        impu: "sip:user@ims",
        pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=123",
        localIP: "10.0.0.5",
        localPort: 5060,
        destinationURI: "tel:112",
        dialog: DialogContext(),
        registration: RegistrationContext(defaultIMPU: "sip:user@ims"),
        sdp: SDPSessionBuilder.voLTEOffer(profile: profile, localIP: "10.0.0.5", audioPort: 40000)
    )
    #expect(invite.headers["Priority"] == "emergency")
    #expect(invite.headers["P-Emergency-Info"] != nil)
}

/// Placing an emergency call through CallService must establish a session even when
/// the UE was already registered — emulating a user dialing 112 from the phone app.
@Test func placeEmergencyCallViaCallService() async throws {
    var profile = try loadFixtureProfile()
    profile.services.emergency.enabled = true
    let (service, _) = try await registeredCallService(profile: profile)
    let session = try await service.placeEmergencyCall()
    #expect(session.state == .established)
    try await service.hangUp()
}

/// When emergency is disabled in the profile, placeEmergencyCall must reject the
/// request rather than sending an unauthorized emergency INVITE.
@Test func emergencyDisabledThrows() async throws {
    var profile = try loadFixtureProfile()
    profile.services.emergency.enabled = false
    let (service, _) = try await registeredCallService(profile: profile)
    do {
        _ = try await service.placeEmergencyCall()
        Issue.record("Expected emergency disabled error")
    } catch EmergencyError.disabled {
        // expected
    }
}

// MARK: - SMS & Supplementary

/// SMS with 3GPP binary payload enabled must complete the SIP MESSAGE transaction
/// against the mock IMS after registration.
@Test func sendSMSWith3GPPPayload() async throws {
    var profile = try loadFixtureProfile()
    profile.services.sms.enabled = true
    profile.services.sms.use3GPPPayload = true
    let state = MockIMSState()
    let transport = makeMockIMSTransport(profile: profile, state: state)
    let service = try makeCallService(profile: profile, transport: transport)
    try await service.register(expires: 60)
    try await service.sendSMS(to: "tel:+15551212", text: "3GPP SMS")
}

/// SMS disabled in profile must throw SMSError.disabled before any MESSAGE is sent.
@Test func smsDisabledThrows() async throws {
    var profile = try loadFixtureProfile()
    profile.services.sms.enabled = false
    let (service, _) = try await registeredCallService(profile: profile)
    do {
        try await service.sendSMS(to: "tel:+1", text: "hi")
        Issue.record("Expected SMS disabled")
    } catch SMSError.disabled {
        // expected
    }
}

/// XCAP requests for supplementary services use HTTP Digest; the wrapper must
/// authenticate GET requests against the in-memory XCAP backend.
@Test func digestXCAPTransportWrapsInMemoryBackend() async throws {
    let inner = InMemoryXCAPTransport()
    let digest = DigestXCAPTransport(
        wrapping: inner,
        credentials: XCAPDigestCredentials(username: "user", password: "pass")
    )
    let url = URL(string: "http://xcap.example/xcap-root/users/sip:user@ims/servinfo.xml")!
    let (status, _) = try await digest.get(url: url)
    #expect(status == 404)
}

/// Supplementary services disabled in profile must throw XCAPError.disabled for
/// call forwarding fetch/set operations.
@Test func supplementaryDisabledThrows() async throws {
    var profile = try loadFixtureProfile()
    profile.services.supplementary.enabled = false
    let (service, _) = try await registeredCallService(profile: profile)
    do {
        _ = try await service.fetchCallForwarding()
        Issue.record("Expected XCAP disabled")
    } catch XCAPError.disabled {
        // expected
    }
}

// MARK: - CallService session features

/// DTMF digits sent during an active MO call with media enabled must traverse the
/// RTP telephone-event path — used for IVR and voicemail PIN entry.
@Test func callServiceDTMFOnActiveCall() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let bridge = LoopbackRTPBridge()
    let transport = makeMockIMSTransport(profile: profile, state: state)
    let service = try makeCallService(
        profile: profile,
        transport: transport,
        enableMedia: true,
        mediaTransportFactory: MediaBootstrap.sharedLoopbackFactory(bridge: bridge)
    )
    try await service.register(expires: 60)
    _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    try await service.sendDTMF("5")
    try await service.hangUp()
}

/// Placing a second MO call while one is active must auto-hold the first (3GPP
/// explicit communication transfer behavior) and restore it when the second ends.
@Test func secondMOCallAutoHoldsFirst() async throws {
    let profile = try loadFixtureProfile()
    let dest1 = "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org"
    let dest2 = "sip:001010111111111@ims.mnc001.mcc001.3gppnetwork.org"
    let (service, _) = try await registeredCallService(profile: profile)

    _ = try await service.placeCall(to: dest1)
    _ = try await service.placeCall(to: dest2)

    #expect(await service.heldSession()?.remoteURI == dest1)
    #expect(await service.activeSession()?.remoteURI == dest2)
    #expect(await service.heldSession()?.mediaDirection == .sendonly)

    try await service.hangUp()
    #expect(await service.activeSession()?.remoteURI == dest1)
    #expect(await service.heldSession() == nil)

    try await service.hangUp()
    #expect(await service.activeSession() == nil)
}

/// If registration refresh fails (403), the active call must be torn down because
/// the IMS binding is no longer valid — the UE cannot maintain media without reg.
@Test func registrationLossTerminatesActiveCall() async throws {
    var profile = try loadFixtureProfile()
    profile.timers.registrationRefreshRatio = 0.05
    let state = MockPCSCFState()
    let imsState = MockIMSState()
    let fixedProfile = profile

    let transport = LoopbackSIPTransport { data in
        guard case .request(let request) = try? SIPParser.parse(data) else { return [] }
        switch request.method {
        case SIPMethod.register.rawValue:
            if state.registered,
               request.headers["Authorization"] != nil,
               let creds = DigestAuthParser.parseCredentials(request.headers["Authorization"] ?? ""),
               !creds.response.isEmpty || creds.auts != nil {
                return [SIPSerializer.serialize(.response(SIPResponse(statusCode: 403, reasonPhrase: "Forbidden")))]
            }
            guard let response = MockPCSCFResponder.response(for: data, profile: fixedProfile, state: state) else {
                return []
            }
            return [response]
        default:
            return MockIMSResponder.responses(for: data, profile: fixedProfile, state: imsState)
        }
    }

    let service = try makeCallService(profile: profile, transport: transport)
    try await service.register(expires: 20)
    _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    #expect(await service.activeSession() != nil)

    try await Task.sleep(for: .milliseconds(1500))
    #expect(await service.activeSession() == nil)
}

/// After an MO call with loopback media, mediaStats must report packets sent —
/// confirming RTP is flowing for QoS monitoring and debug UI.
@Test func callServiceMediaStatsAfterMOCall() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let bridge = LoopbackRTPBridge()
    let transport = makeMockIMSTransport(profile: profile, state: state)
    let service = try makeCallService(
        profile: profile,
        transport: transport,
        enableMedia: true,
        mediaTransportFactory: MediaBootstrap.sharedLoopbackFactory(bridge: bridge)
    )
    try await service.register(expires: 60)
    _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    try await Task.sleep(for: .milliseconds(80))
    let stats = await service.mediaStats()
    #expect(stats.packetsSent >= 1)
    try await service.hangUp()
}

/// Wi-Fi → LTE handover changes IP and PANI; CallService must re-REGISTER while
/// staying registered so inbound calls reach the new contact address.
@Test func callServiceNetworkPathChangeWhileRegistered() async throws {
    var profile = try loadFixtureProfile()
    let fixedProfile = profile
    let state = MockPCSCFState()
    let network = MutableStubNetworkAdapter(localIP: "10.0.0.5", pathLabel: "wifi:ap1")
    let access = MutableStubAccessInfoAdapter(
        accessInfo: AccessInfo(rat: .ieee80211, cellOrAPIdentifier: "ap1")
    )
    let sim = LabSimAdapter(config: try #require(profile.labSim))
    let transport = LoopbackSIPTransport { data in
        guard let response = MockPCSCFResponder.response(for: data, profile: fixedProfile, state: state) else {
            return []
        }
        return [response]
    }
    let platform = PlatformContext(
        sim: sim,
        network: network,
        bearer: StubBearerAdapter(),
        accessInfo: access
    )
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: Logger(output: { _ in }),
        enableMedia: false
    )
    try await service.register(expires: 60)
    let before = state.registerAttemptCount
    network.setNetworkSnapshot(localIP: "10.0.0.9", pathLabel: "lte:cell2")
    access.setAccessInfo(AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "cell2"))
    try await service.handleNetworkPathChange()
    #expect(state.registerAttemptCount > before)
    #expect(await service.registrationState() == .registered)
}

// MARK: - Media & codecs

/// Lab AMR-WB codec engine must round-trip PCM → RTP payload → PCM for voice
/// frame processing in the media pipeline.
@Test func labAmrCodecEngineRoundTrip() {
    let engine = LabAMRCodecEngine(codec: .amrWB)
    let pcm = Data(repeating: 0x42, count: 320)
    let encoded = engine.encodePCM(pcm)
    #expect(!encoded.isEmpty)
    let decoded = engine.decodeRTPPayload(encoded)
    #expect(!decoded.isEmpty)
    #expect(engine.codec == .amrWB)
}

/// Default lab profiles select LabAMRCodecEngine for AMR-WB — the standard VoLTE codec.
@Test func mediaBootstrapSelectsLabAMRByDefault() throws {
    let profile = try loadFixtureProfile()
    let engine = MediaBootstrap.codecEngine(for: .amrWB, profile: profile)
    #expect(engine.codec == .amrWB)
    #expect(engine is LabAMRCodecEngine)
}

/// Premium EVS profiles select LabEVSCodecEngine when FFmpeg is not enabled.
@Test func mediaBootstrapSelectsEVSForPremiumCodec() throws {
    var profile = try loadPremiumProfile()
    profile.media.useFFmpegCodec = false
    let engine = MediaBootstrap.codecEngine(for: .evs, profile: profile)
    #expect(engine is LabEVSCodecEngine)
}

// MARK: - Diagnostics & transport recording

/// RecordingSIPTransport wraps any transport and feeds packets to PcapExporter for
/// Wireshark-compatible capture of SIP signaling.
@Test func recordingSIPTransportCapturesViaPcapExporter() async throws {
    let exporter = PcapExporter(enabled: true)
    let inner = LoopbackSIPTransport { _ in [] }
    let recording = RecordingSIPTransport(wrapping: inner, exporter: exporter)
    let payload = Data("OPTIONS sip:pcscf SIP/2.0\r\n\r\n".utf8)
    try await recording.send(payload)
    #expect(exporter.packetCount() == 1)
}

/// UDP signaling connections use CRLF keep-alive pings to maintain NAT bindings;
/// reliable transports use SIP OPTIONS instead.
@Test func sipKeepAliveUsesCRLFOnUDP() throws {
    let profile = try loadFixtureProfile()
    final class UDPStub: @unchecked Sendable, SIPTransport {
        let isReliable = false
        func connect() async throws {}
        func send(_: Data) async throws {}
        func receive(timeout: Duration) async throws -> Data? { nil }
        func close() async {}
    }
    let strategy = SIPKeepAlive.strategy(
        transport: UDPStub(),
        profile: profile,
        impu: "sip:user@ims",
        localIP: "127.0.0.1",
        localPort: 5060,
        context: RegistrationContext()
    )
    if case .crlf = strategy {
        let payload = SIPKeepAlive.payload(for: strategy)
        #expect(payload == Data("\r\n\r\n".utf8))
    } else {
        Issue.record("Expected CRLF keep-alive on UDP")
    }
}

// MARK: - Resilience policies

/// 403 Forbidden is permanent — registration must not retry (e.g. barred subscriber).
@Test func retryPolicyDoesNotRetry403() {
    #expect(!RetryPolicy.shouldRetryRegistration(
        statusCode: 403,
        error: RegistrationError.unexpectedStatus(403),
        attempt: 1,
        maxAttempts: 3
    ))
}

/// 408 Request Timeout is transient — registration should retry up to maxAttempts.
@Test func retryPolicyRetries408() {
    #expect(RetryPolicy.shouldRetryRegistration(
        statusCode: 408,
        error: RegistrationError.unexpectedStatus(408),
        attempt: 1,
        maxAttempts: 3
    ))
}

// MARK: - Handover / STIR-SHAK

/// STIR/SHAKEN disabled means no Identity header on outbound INVITE — callers
/// are not attested until the operator enables the feature.
@Test func stirShakDisabledOmitsIdentityHeader() throws {
    var profile = try loadFixtureProfile()
    profile.services.handover.stirShakEnabled = false
    var headers = SIPHeaders()
    STIRSHAKPolicy.attachIdentity(to: &headers, profile: profile)
    #expect(headers["Identity"] == nil)
}

/// eSRVCC handover must send SIP REFER to transfer the active dialog to the CS
/// domain anchor when the UE moves from LTE to 2G/3G during a voice call.
@Test func esrvccCoordinatorSendsReferOnBegin() async throws {
    var profile = try loadFixtureProfile()
    profile.services.handover.esrvccEnabled = true
    let adapter = StubHandoverAdapter()
    let sent = LineCollector()
    let transport = LoopbackSIPTransport { data in
        if let message = try? SIPParser.parse(data), case .request(let req) = message {
            sent.append(req.method)
        }
        return []
    }
    let sessionFSM = SessionFSM(
        profile: profile,
        platform: try PlatformContext.stubbed(profile: profile),
        transport: transport,
        logger: Logger(output: { _ in })
    )
    await sessionFSM.injectSessionsForTesting(
        active: SessionContext(
            dialog: DialogContext(callID: "esrvcc-1", remoteTarget: "sip:peer@ims"),
            state: .established,
            remoteURI: "sip:peer@ims",
            localURI: "sip:user@ims"
        ),
        held: nil
    )
    let coordinator = ESRVCCCoordinator(
        profile: profile,
        handoverAdapter: adapter,
        transport: transport,
        logger: Logger(output: { _ in }),
        sessionProvider: { await sessionFSM.activeSessionContext() }
    )
    await coordinator.beginHandover(callID: "esrvcc-1")
    #expect(sent.snapshot.contains(SIPMethod.refer.rawValue))
}

// MARK: - Application bootstrap

/// Application bootstrap must load the profile, build PlatformContext, and discover
/// the P-CSCF endpoint before any SIP signaling begins.
@Test func applicationLoadsProfileAndBuildsContext() throws {
    let profile = try loadFixtureProfile()
    let platform = try PlatformContext.stubbed(profile: profile)
    let endpoint = try platform.network.discoverPCSCF(profile: profile)
    #expect(endpoint.host == "10.0.0.1")
}

import Security
