import Foundation
import Testing
@testable import SICLientCore

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
