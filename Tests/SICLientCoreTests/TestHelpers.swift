// TestHelpers.swift
//
// Shared test utilities for SICLientCoreTests: log collectors, fixture profile loaders,
// mock IMS transport wiring, and pre-registered CallService factories. These helpers
// let individual test files focus on IMS behavior rather than boilerplate setup.

import Foundation
@testable import SICLientCore

// MARK: - Log capture

/// Thread-safe collector for structured log lines emitted during tests.
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

// MARK: - Fixture profiles

/// Resolves a JSON operator profile from the repo's profiles/ directory.
func fixtureURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../profiles/\(name)")
        .standardizedFileURL
}

/// Standard lab VoLTE profile used by most core tests (static P-CSCF, AMR-WB, lab SIM).
func loadFixtureProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: fixtureURL(named: "lab-volte-01.json"))
}

/// Premium profile with EVS codec for codec-selection tests.
func loadPremiumProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: fixtureURL(named: "lab-volte-evs-premium.json"))
}

// MARK: - Mock transport & CallService factories

/// Loopback SIP transport that routes REGISTER to mock P-CSCF and everything else to mock IMS.
func makeMockIMSTransport(
    profile: OperatorProfile,
    state: MockIMSState = MockIMSState()
) -> LoopbackSIPTransport {
    let fixedProfile = profile
    return LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: fixedProfile, state: state)
    }
}

/// Builds a CallService wired to stub platform adapters and a provided transport.
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

/// Convenience: register against mock P-CSCF/IMS and return a ready CallService.
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
