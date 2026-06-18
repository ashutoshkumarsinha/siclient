// Phase5Tests.swift
//
// Verifies Phase 5 IMS features: emergency registration/calls, SMS over SIP MESSAGE,
// XCAP supplementary services (call forwarding), EVS codec, STIR/SHAKEN identity,
// and eSRVCC handover hooks. These are carrier-mandatory services beyond basic VoLTE.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Emergency services

/// Emergency REGISTER must carry Priority, Resource-Priority, P-Emergency-Info, and
/// +g.3gpp.emergency in Contact so the IMS routes the UE to PSAP even if unregistered.
@Test func emergencyRegisterIncludesPriorityHeaders() throws {
    var profile = try loadFixtureProfile()
    profile.services.emergency.enabled = true

    let request = EmergencyRequestBuilder.makeEmergencyRegister(
        profile: profile,
        impi: "user@ims.example",
        impu: "sip:user@ims.example",
        pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=234150999010203",
        localIP: "10.0.0.5",
        localPort: 5060,
        context: RegistrationContext(),
        credentials: nil,
        expires: 3600
    )

    #expect(request.headers["Priority"] == "emergency")
    #expect(request.headers["Resource-Priority"] == "wps.4")
    #expect(request.headers["P-Emergency-Info"] == "urn:service:sos")
    #expect(request.headers["Contact"]?.contains("+g.3gpp.emergency") == true)
}

// MARK: - SMS over IMS

/// SIP MESSAGE for SMS must include the icsi.sms feature tag in Accept-Contact so the
/// SMSC knows this is a 3GPP SMS-over-IMS session, not a generic instant message.
@Test func smsMessageBuilderIncludesICSI() throws {
    var profile = try loadFixtureProfile()
    profile.services.sms.enabled = true
    let registration = RegistrationContext(defaultIMPU: "sip:user@ims.example", expiresSec: 3600)

    let message = SMSRequestBuilder.makeMESSAGE(
        profile: profile,
        impu: "sip:user@ims.example",
        pani: "3GPP-E-UTRAN-FDD;utran-cell-id-3gpp=234150999010203",
        localIP: "10.0.0.5",
        localPort: 5060,
        destinationURI: "tel:+15551212",
        registration: registration,
        text: "Hello IMS"
    )

    #expect(message.method == SIPMethod.message.rawValue)
    #expect(message.headers["Accept-Contact"]?.contains("icsi.sms") == true)
    #expect(String(decoding: message.body ?? Data(), as: UTF8.self) == "Hello IMS")
}

/// End-to-end SMS send after registration proves the MESSAGE transaction completes
/// against the mock IMS core (RP-DATA encapsulation handled internally).
@Test func sendSMSOverLoopbackIMS() async throws {
    var profile = try loadFixtureProfile()
    profile.services.sms.enabled = true
    let fixedProfile = profile
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: fixedProfile, state: state)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        enableMedia: false
    )

    try await service.register(expires: 60)
    try await service.sendSMS(to: "tel:+15551212", text: "Phase 5 SMS")
}

// MARK: - Supplementary services (XCAP)

/// Call forwarding rules are stored as XCAP XML documents; serialize/parse must
/// preserve active flag and target number for CFU (Call Forwarding Unconditional).
@Test func callForwardingDocumentRoundTrip() {
    let rule = CallForwardingRule(active: true, target: "tel:+15559876")
    let xml = CallForwardingDocument.serialize(rule: rule)
    let parsed = CallForwardingDocument.parse(xml)
    #expect(parsed.active)
    #expect(parsed.target == "tel:+15559876")
}

/// Setting and fetching call forwarding via in-memory XCAP proves the supplementary
/// service API works after IMS registration (used by carrier self-care apps).
@Test func supplementaryCallForwardingInMemoryXCAP() async throws {
    var profile = try loadFixtureProfile()
    profile.services.supplementary.enabled = true
    let fixedProfile = profile
    let state = MockPCSCFState()
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let transport = LoopbackSIPTransport { data in
        guard let response = MockPCSCFResponder.response(for: data, profile: fixedProfile, state: state) else {
            return []
        }
        return [response]
    }
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        enableMedia: false
    )

    try await service.register(expires: 60)
    try await service.setCallForwarding(active: true, target: "tel:+100")
    let rule = try await service.fetchCallForwarding()
    #expect(rule.active)
    #expect(rule.target == "tel:+100")
}

// MARK: - EVS codec

/// Premium profiles prefer EVS (Enhanced Voice Services) for HD voice; the SDP offer
/// must advertise EVS payload type 110 ahead of legacy AMR codecs.
@Test func evsCodecAppearsInPremiumOffer() throws {
    var profile = try loadFixtureProfile()
    profile.codecs.audio = ["EVS", "AMR-WB", "AMR"]
    let offer = SDPSessionBuilder.voLTEOffer(
        profile: profile,
        localIP: "127.0.0.1",
        audioPort: 40000
    )
    let text = offer.serialize()
    #expect(text.contains("a=rtpmap:110 EVS/16000"))
    #expect(offer.media.first?.formats.first == "110")
    #expect(SDPParser.offeredAudioCodecs(offer).contains(.evs))
}

/// The lab EVS codec engine must produce non-empty RTP payloads from PCM input for
/// media session tests without requiring FFmpeg in CI.
@Test func labEvsCodecEngineFraming() {
    let engine = LabEVSCodecEngine()
    let payload = engine.encodePCM(Data(repeating: 0x11, count: 64))
    #expect(!payload.isEmpty)
    #expect(engine.codec == .evs)
}

// MARK: - STIR/SHAKEN caller ID

/// When enabled, outbound INVITEs carry an Identity header for STIR/SHAKEN attestation,
/// helping called parties verify the caller is not spoofed.
@Test func stirShakIdentityAttachedWhenEnabled() throws {
    var profile = try loadFixtureProfile()
    profile.services.handover.stirShakEnabled = true
    profile.services.handover.labIdentityHeader = "eyJ0eXAiOiJwYXNwb3J0IiwicGF5bG9hZCI6ImxhYiJ9"

    var headers = SIPHeaders()
    STIRSHAKPolicy.attachIdentity(to: &headers, profile: profile)
    #expect(headers["Identity"]?.hasPrefix("eyJ") == true)
}

// MARK: - eSRVCC handover

/// Enhanced Single Radio Voice Call Continuity moves an active call from LTE to 3G/2G.
/// begin/complete hooks must fire so the session can send REFER and update media anchors.
@Test func esrvccHandoverHooksFire() async throws {
    var profile = try loadFixtureProfile()
    profile.services.handover.esrvccEnabled = true
    let fixedProfile = profile
    let adapter = StubHandoverAdapter()
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: fixedProfile, state: state)
    }
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        enableMedia: false,
        handoverAdapter: adapter
    )

    try await service.register(expires: 60)
    _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    try await service.beginESRVCCHandover()
    try await service.completeESRVCCHandover()
    #expect(await service.handoverEvents().count == 2)
    try await service.hangUp()
}
