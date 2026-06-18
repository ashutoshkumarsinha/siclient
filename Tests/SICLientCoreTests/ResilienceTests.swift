import Foundation
import Testing
@testable import SICLientCore

@Test func transportPolicyDetectsLargePayloads() {
    #expect(TransportPolicy.exceedsMTU(1301, limit: 1300))
    #expect(!TransportPolicy.exceedsMTU(1300, limit: 1300))
    #expect(TransportPolicy.fallbackProtocol(for: [.udp, .tcp, .tls], current: .udp) == .tcp)
}

@Test func fallbackTransportUsesTCPForLargePayload() async throws {
    final class RecordingTransport: @unchecked Sendable, SIPTransport {
        var isReliable: Bool
        var sentPayloads: [Data] = []
        var connectCount = 0

        init(isReliable: Bool) {
            self.isReliable = isReliable
        }

        func connect() async throws { connectCount += 1 }
        func send(_ data: Data) async throws { sentPayloads.append(data) }
        func receive(timeout: Duration) async throws -> Data? { nil }
        func close() async {}
    }

    let udp = RecordingTransport(isReliable: false)
    let tcp = RecordingTransport(isReliable: true)
    let transport = FallbackSIPTransport(primary: udp, fallback: tcp, mtuLimit: 100)

    try await transport.connect()
    let large = Data(repeating: 0xAB, count: 150)
    try await transport.send(large)

    #expect(transport.lastSendUsedFallback)
    #expect(tcp.sentPayloads.count == 1)
    #expect(udp.sentPayloads.isEmpty)
}

@Test func registrationRetriesOn503() async throws {
    let profile = try loadFixtureProfile()
    let state = MockPCSCFState()
    final class RetryState: @unchecked Sendable { var serviceUnavailableSent = false }
    let retryState = RetryState()

    let transport = LoopbackSIPTransport { data in
        guard case .request(let request) = try? SIPParser.parse(data),
              request.method == SIPMethod.register.rawValue else { return [] }
        if !retryState.serviceUnavailableSent {
            retryState.serviceUnavailableSent = true
            return [SIPSerializer.serialize(.response(SIPResponse(statusCode: 503, reasonPhrase: "Service Unavailable")))]
        }
        guard let response = MockPCSCFResponder.response(for: data, profile: profile, state: state) else {
            return []
        }
        return [response]
    }

    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    try await fsm.register(expires: 60)
    #expect(state.registerAttemptCount >= 2)
    #expect(await fsm.currentState() == .registered)
}

@Test func networkPathChangeTriggersReregister() async throws {
    let profile = try loadFixtureProfile()
    let state = MockPCSCFState()
    let network = MutableStubNetworkAdapter(localIP: "10.0.0.5", pathLabel: "wifi:ap1")
    let access = MutableStubAccessInfoAdapter(
        accessInfo: AccessInfo(rat: .ieee80211, cellOrAPIdentifier: "ap1")
    )
    let sim = LabSimAdapter(config: try #require(try loadFixtureProfile().labSim))

    let transport = LoopbackSIPTransport { data in
        guard let response = MockPCSCFResponder.response(for: data, profile: profile, state: state) else {
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

    let logger = Logger(output: { _ in })
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)
    try await fsm.register(expires: 60)
    let before = state.registerAttemptCount

    network.setNetworkSnapshot(localIP: "10.0.0.9", pathLabel: "lte:cell2")
    access.setAccessInfo(AccessInfo(rat: .eutranFDD, cellOrAPIdentifier: "cell2"))
    try await fsm.handleNetworkPathChange()

    #expect(state.registerAttemptCount > before)
    #expect(await fsm.currentState() == .registered)
}

@Test func optionsKeepAliveOnReliableTransport() throws {
    let profile = try loadFixtureProfile()
    final class ReliableStub: @unchecked Sendable, SIPTransport {
        let isReliable = true
        func connect() async throws {}
        func send(_: Data) async throws {}
        func receive(timeout: Duration) async throws -> Data? { nil }
        func close() async {}
    }

    let context = RegistrationContext(
        serviceRoute: "<sip:pcscf.example;lr>",
        defaultIMPU: "sip:user@example",
        expiresSec: 3600
    )
    let strategy = SIPKeepAlive.strategy(
        transport: ReliableStub(),
        profile: profile,
        impu: "sip:user@example",
        localIP: "127.0.0.1",
        localPort: 5060,
        context: context
    )

    if case .options(let request) = strategy {
        #expect(request.method == SIPMethod.options.rawValue)
    } else {
        Issue.record("Expected OPTIONS keep-alive on reliable transport")
    }
}

@Test func retryPolicyHonorsRetryAfter() {
    var headers = SIPHeaders()
    headers.set("Retry-After", value: "2")
    let response = SIPResponse(
        statusCode: 503,
        reasonPhrase: "Service Unavailable",
        headers: headers
    )
    #expect(RetryPolicy.retryAfterHeader(from: response) == .seconds(2))
}
