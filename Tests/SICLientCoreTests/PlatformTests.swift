import Foundation
import Testing
@testable import SICLientCore

@Test func stubNetworkDiscoversStaticPCSCF() throws {
    let profile = try loadFixtureProfile()
    let network = StubNetworkAdapter()
    let endpoint = try network.discoverPCSCF(profile: profile)

    #expect(endpoint.host == "10.0.0.1")
    #expect(endpoint.port == 5060)
    #expect(endpoint.transport == .udp)
}

@Test func stubAccessInfoBuildsPANI() throws {
    let adapter = StubAccessInfoAdapter()
    let info = try adapter.currentAccessInfo()

    #expect(info.paniHeaderValue.contains("3GPP-E-UTRAN-FDD"))
    #expect(info.paniHeaderValue.contains("utran-cell-id-3gpp="))
}

@Test func stubBearerLifecycle() throws {
    let bearer = StubBearerAdapter()
    let handle = try bearer.requestDedicatedBearer(qci: .voice)
    #expect(bearer.activeBearerCount == 1)
    try bearer.releaseBearer(handle)
    #expect(bearer.activeBearerCount == 0)
}

@Test func platformContextUsesLabSim() throws {
    let profile = try loadFixtureProfile()
    let context = try PlatformContext.stubbed(profile: profile)

    let impi = try context.sim.getIMPI()
    let impus = try context.sim.getIMPUList()

    #expect(impi.contains("001010123456789"))
    #expect(impus.count == 2)
}
