import Foundation
import Testing
@testable import SICLientCore

// MARK: - Registration & Authentication

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

@Test func parseDigestCredentialsWithAUTS() throws {
    let header = #"Digest username="user", realm="ims", nonce="n", uri="sip:ims", auts="abc123==""#
    let creds = try #require(DigestAuthParser.parseCredentials(header))
    #expect(creds.auts == "abc123==")
    #expect(creds.response.isEmpty)
}

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

@Test func simAdapterFactorySelectsLabSim() throws {
    let profile = try loadFixtureProfile()
    let adapter = SimAdapterFactory.make(profile: profile)
    let impi = try adapter.getIMPI()
    #expect(impi.contains("001010123456789"))
}

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

@Test func tlsConfigLabInsecureAllowsBypass() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.security.tls.allowInsecureLab == true)
}

// MARK: - Discovery & Platform

@Test func dhcpDiscoveryFromProfile() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.mode = .dhcp
    profile.pcscf.dhcpAddresses = ["10.20.30.40:5070"]
    let adapter = ProductionNetworkAdapter()
    let endpoint = try adapter.discoverPCSCF(profile: profile)
    #expect(endpoint.host == "10.20.30.40")
    #expect(endpoint.port == 5070)
}

@Test func stubNetworkResolvesHostnameMap() throws {
    let adapter = StubNetworkAdapter(resolvedHosts: ["pcscf.ims": ["10.0.0.99"]])
    #expect(try adapter.resolveHostname("pcscf.ims") == ["10.0.0.99"])
    #expect(try adapter.resolveHostname("unknown.example") == ["unknown.example"])
}

@Test func transportFactoryCreatesFallbackForUDPProfile() throws {
    let profile = try loadFixtureProfile()
    let endpoint = PCSCFEndpoint(host: "10.0.0.1", port: 5060, transport: .udp)
    let transport = TransportFactory.make(endpoint: endpoint, profile: profile)
    #expect(transport is FallbackSIPTransport)
}

// MARK: - Configuration

@Test func loadsPremiumEVSProfile() throws {
    let profile = try loadPremiumProfile()
    #expect(profile.codecs.audio.first == "EVS")
    #expect(profile.profileID.contains("evs") || profile.codecs.audio.contains("EVS"))
}

@Test func profileServicesConfigRoundTrip() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.services.emergency.enabled)
    #expect(profile.services.sms.enabled)
    #expect(profile.services.supplementary.enabled)
    #expect(profile.services.handover.esrvccEnabled)
    #expect(profile.media.localRTPPort == 40_000)
    #expect(profile.resilience.maxRegistrationRetries == 3)
}

@Test func profileValidationAcceptsPCOAddresses() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.mode = .pco
    profile.pcscf.pcoAddresses = ["10.0.0.2:5060"]
    try ProfileValidator.validate(profile)
}

// MARK: - Emergency

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

@Test func placeEmergencyCallViaCallService() async throws {
    var profile = try loadFixtureProfile()
    profile.services.emergency.enabled = true
    let (service, _) = try await registeredCallService(profile: profile)
    let session = try await service.placeEmergencyCall()
    #expect(session.state == .established)
    try await service.hangUp()
}

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

@Test func labAmrCodecEngineRoundTrip() {
    let engine = LabAMRCodecEngine(codec: .amrWB)
    let pcm = Data(repeating: 0x42, count: 320)
    let encoded = engine.encodePCM(pcm)
    #expect(!encoded.isEmpty)
    let decoded = engine.decodeRTPPayload(encoded)
    #expect(!decoded.isEmpty)
    #expect(engine.codec == .amrWB)
}

@Test func mediaBootstrapSelectsLabAMRByDefault() throws {
    let profile = try loadFixtureProfile()
    let engine = MediaBootstrap.codecEngine(for: .amrWB, profile: profile)
    #expect(engine.codec == .amrWB)
    #expect(engine is LabAMRCodecEngine)
}

@Test func mediaBootstrapSelectsEVSForPremiumCodec() throws {
    var profile = try loadPremiumProfile()
    profile.media.useFFmpegCodec = false
    let engine = MediaBootstrap.codecEngine(for: .evs, profile: profile)
    #expect(engine is LabEVSCodecEngine)
}

// MARK: - Diagnostics & transport recording

@Test func recordingSIPTransportCapturesViaPcapExporter() async throws {
    let exporter = PcapExporter(enabled: true)
    let inner = LoopbackSIPTransport { _ in [] }
    let recording = RecordingSIPTransport(wrapping: inner, exporter: exporter)
    let payload = Data("OPTIONS sip:pcscf SIP/2.0\r\n\r\n".utf8)
    try await recording.send(payload)
    #expect(exporter.packetCount() == 1)
}

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

@Test func retryPolicyDoesNotRetry403() {
    #expect(!RetryPolicy.shouldRetryRegistration(
        statusCode: 403,
        error: RegistrationError.unexpectedStatus(403),
        attempt: 1,
        maxAttempts: 3
    ))
}

@Test func retryPolicyRetries408() {
    #expect(RetryPolicy.shouldRetryRegistration(
        statusCode: 408,
        error: RegistrationError.unexpectedStatus(408),
        attempt: 1,
        maxAttempts: 3
    ))
}

// MARK: - Handover / STIR-SHAK

@Test func stirShakDisabledOmitsIdentityHeader() throws {
    var profile = try loadFixtureProfile()
    profile.services.handover.stirShakEnabled = false
    var headers = SIPHeaders()
    STIRSHAKPolicy.attachIdentity(to: &headers, profile: profile)
    #expect(headers["Identity"] == nil)
}

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

@Test func applicationLoadsProfileAndBuildsContext() throws {
    let profile = try loadFixtureProfile()
    let platform = try PlatformContext.stubbed(profile: profile)
    let endpoint = try platform.network.discoverPCSCF(profile: profile)
    #expect(endpoint.host == "10.0.0.1")
}

import Security
