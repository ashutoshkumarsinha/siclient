// PerformanceTests.swift
//
// Verifies non-functional requirements (NFRs) for registration and call-setup latency.
// Carriers specify maximum times for attach-to-registered and MO call establishment;
// these tests ensure the client meets those targets in the lab loopback environment.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Registration latency

/// Full REGISTER flow (401 challenge + AKA + 200 OK) must complete within the NFR budget
/// so users don't wait excessively after LTE attach before VoLTE is available.
@Test func registrationMeetsNFRTarget() async throws {
    let profile = try loadFixtureProfile()
    let state = MockPCSCFState()
    let transport = LoopbackSIPTransport { data in
        MockPCSCFResponder.response(for: data, profile: profile, state: state).map { [$0] } ?? []
    }

    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let fsm = RegistrationFSM(profile: profile, platform: platform, transport: transport, logger: logger)

    let durationMs = try await PerformanceTimer.measureMilliseconds {
        try await fsm.register(expires: 60)
    }

    #expect(PerformanceBenchmarks.meetsRegistrationTarget(durationMs))
}

// MARK: - Call setup latency

/// Mobile-originated call setup (INVITE through 200 OK) must meet the NFR target.
/// Slow setup directly affects perceived call quality and network KPIs.
@Test func moCallSetupMeetsNFRTarget() async throws {
    let profile = try loadFixtureProfile()
    let state = MockIMSState()
    let transport = LoopbackSIPTransport { data in
        MockIMSResponder.responses(for: data, profile: profile, state: state)
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

    let durationMs = try await PerformanceTimer.measureMilliseconds {
        _ = try await service.placeCall(to: "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org")
    }

    #expect(PerformanceBenchmarks.meetsCallSetupTarget(durationMs))
    try await service.hangUp()
}
