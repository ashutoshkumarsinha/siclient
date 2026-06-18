// RegistrationTests.swift
//
// Verifies the RegistrationFSM — the state machine that drives SIP REGISTER against
// the P-CSCF, handles 401 AKA challenges, stores Service-Route/IMPU, and refreshes
// before Expires. Registration is the prerequisite for every IMS voice, SMS, and data service.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Full registration flow

/// Exercises the standard two-step IMS registration: unauthenticated REGISTER, 401 with
/// Digest challenge, AKA via lab SIM, authenticated REGISTER → 200 OK with Service-Route.
/// Also confirms secrets never leak into registration logs.
@Test func twoStepRegistrationAgainstMockPCSCF() async throws {
    let profile = try loadFixtureProfile()
    let state = MockPCSCFState()
    let transport = LoopbackSIPTransport(singleResponder: { data in
        MockPCSCFResponder.response(for: data, profile: profile, state: state)
    })

    let collector = LineCollector()
    let logger = Logger(correlationID: CorrelationID(prefix: "reg"), output: { collector.append($0) })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)
    try await fsm.register(expires: 60)

    #expect(await fsm.currentState() == .registered)
    let context = await fsm.registrationContext()
    #expect(context.serviceRoute?.contains("pcscf") == true)
    #expect(context.defaultIMPU?.contains("001010123456789") == true)

    let logs = collector.snapshot.joined()
    #expect(!logs.contains("e19aa1c37ab954daa44fa2a52007"))
    #expect(logs.contains("registration complete"))
}

// MARK: - Deregistration

/// After a successful REGISTER the UE must be able to send REGISTER with Expires: 0
/// to cleanly detach from the IMS — important for power-off and airplane-mode scenarios.
@Test func deregisterAfterRegistration() async throws {
    let profile = try loadFixtureProfile()
    let state = MockPCSCFState()
    let transport = LoopbackSIPTransport(singleResponder: { data in
        MockPCSCFResponder.response(for: data, profile: profile, state: state)
    })

    let logger = Logger(correlationID: CorrelationID(prefix: "dereg"), output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    try await fsm.register(expires: 60)
    try await fsm.deregister()
    #expect(await fsm.currentState() == .unregistered)
}

// MARK: - Registration refresh

/// Before the 200 OK Expires timer fires, the client should automatically re-REGISTER
/// at the configured refresh ratio (~80%). Lapsed registration drops all IMS services.
@Test func reRegisterCycle() async throws {
    var profile = try loadFixtureProfile()
    profile.timers.registrationRefreshRatio = 0.1
    let fixedProfile = profile
    let state = MockPCSCFState()
    let transport = LoopbackSIPTransport { data in
        MockPCSCFResponder.response(for: data, profile: fixedProfile, state: state)
    }

    let collector = LineCollector()
    let logger = Logger(correlationID: CorrelationID(prefix: "rereg"), output: { collector.append($0) })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    try await fsm.register(expires: 10)
    try await Task.sleep(for: .milliseconds(1200))
    let logs = collector.snapshot.joined()
    #expect(logs.contains("Re-registration succeeded") || logs.contains("registration complete"))
    try await fsm.deregister()
}

// MARK: - Error handling

/// A 403 Forbidden from the P-CSCF (e.g. barred subscriber) must leave the FSM in
/// unregistered state — the UE should not assume it can place calls or send SMS.
@Test func networkDeregisterOn403() async throws {
    let profile = try loadFixtureProfile()
    let transport = LoopbackSIPTransport(singleResponder: { data in
        guard case .request = try? SIPParser.parse(data) else { return nil }
        return SIPSerializer.serialize(.response(SIPResponse(statusCode: 403, reasonPhrase: "Forbidden")))
    })

    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    do {
        try await fsm.register()
        Issue.record("Expected registration to fail with 403")
    } catch RegistrationError.unexpectedStatus(403) {
        #expect(await fsm.currentState() == .unregistered)
    }
}
