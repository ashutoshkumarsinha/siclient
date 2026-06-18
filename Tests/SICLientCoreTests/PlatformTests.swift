// PlatformTests.swift
//
// Verifies platform abstraction stubs that stand in for real device APIs: network
// discovery, access-network info (P-Access-Network-Info), dedicated bearers, and
// SIM credentials. These layers sit beneath SIP and feed IMS headers like PANI.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - P-CSCF discovery

/// The stub network adapter must resolve a static P-CSCF from the operator profile,
/// matching the first step of VoLTE attach where the UE learns the proxy address.
@Test func stubNetworkDiscoversStaticPCSCF() throws {
    let profile = try loadFixtureProfile()
    let network = StubNetworkAdapter()
    let endpoint = try network.discoverPCSCF(profile: profile)

    #expect(endpoint.host == "10.0.0.1")
    #expect(endpoint.port == 5060)
    #expect(endpoint.transport == .udp)
}

// MARK: - Access network info

/// P-Access-Network-Info (PANI) tells the IMS core which radio cell the UE is on.
/// The stub must produce a valid 3GPP PANI string for inclusion in REGISTER/INVITE.
@Test func stubAccessInfoBuildsPANI() throws {
    let adapter = StubAccessInfoAdapter()
    let info = try adapter.currentAccessInfo()

    #expect(info.paniHeaderValue.contains("3GPP-E-UTRAN-FDD"))
    #expect(info.paniHeaderValue.contains("utran-cell-id-3gpp="))
}

// MARK: - Dedicated bearers

/// Voice calls often request a QCI-1 dedicated bearer for guaranteed bitrate.
/// The stub bearer adapter tracks allocate/release so media setup can be tested.
@Test func stubBearerLifecycle() throws {
    let bearer = StubBearerAdapter()
    let handle = try bearer.requestDedicatedBearer(qci: .voice)
    #expect(bearer.activeBearerCount == 1)
    try bearer.releaseBearer(handle)
    #expect(bearer.activeBearerCount == 0)
}

// MARK: - Platform context assembly

/// PlatformContext bundles SIM, network, bearer, and access-info adapters. With a
/// lab profile it must expose IMPI/IMPU identities used in SIP From/To headers.
@Test func platformContextUsesLabSim() throws {
    let profile = try loadFixtureProfile()
    let context = try PlatformContext.stubbed(profile: profile)

    let impi = try context.sim.getIMPI()
    let impus = try context.sim.getIMPUList()

    #expect(impi.contains("001010123456789"))
    #expect(impus.count == 2)
}
