import Foundation
@testable import SICLientCore

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

func fixtureURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../profiles/\(name)")
        .standardizedFileURL
}

func loadFixtureProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: fixtureURL(named: "lab-volte-01.json"))
}

func loadPremiumProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: fixtureURL(named: "lab-volte-evs-premium.json"))
}

func makeMockIMSTransport(
    profile: OperatorProfile,
    state: MockIMSState = MockIMSState()
) -> LoopbackSIPTransport {
    let fixedProfile = profile
    return LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: fixedProfile, state: state)
    }
}

func makeCallService(
    profile: OperatorProfile,
    transport: any SIPTransport,
    logger: Logger = Logger(output: { _ in }),
    enableMedia: Bool = false,
    mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil,
    handoverAdapter: StubHandoverAdapter? = nil,
    xcapTransport: (any XCAPTransport)? = nil
) throws -> CallService {
    CallService(
        profile: profile,
        platform: try PlatformContext.stubbed(profile: profile),
        transport: transport,
        logger: logger,
        enableMedia: enableMedia,
        mediaTransportFactory: mediaTransportFactory,
        xcapTransport: xcapTransport,
        handoverAdapter: handoverAdapter
    )
}

func registeredCallService(
    profile: OperatorProfile,
    state: MockIMSState = MockIMSState(),
    enableMedia: Bool = false,
    mediaTransportFactory: (@Sendable () -> any RTPTransport)? = nil
) async throws -> (CallService, MockIMSState) {
    let transport = makeMockIMSTransport(profile: profile, state: state)
    let service = try makeCallService(
        profile: profile,
        transport: transport,
        enableMedia: enableMedia,
        mediaTransportFactory: mediaTransportFactory
    )
    try await service.register(expires: 60)
    return (service, state)
}
