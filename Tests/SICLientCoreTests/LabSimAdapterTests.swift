import Foundation
import Testing
@testable import SICLientCore

@Test func labSimReturnsVectorForKnownChallenge() throws {
    let profile = try loadFixtureProfile()
    guard let labSim = profile.labSim else {
        Issue.record("Expected lab_sim in fixture profile")
        return
    }

    let adapter = LabSimAdapter(config: labSim)
    let vector = try #require(labSim.akaVectors.first)

    guard
        let rand = Data(hexString: vector.rand),
        let autn = Data(hexString: vector.autn)
    else {
        Issue.record("Invalid vector hex in fixture")
        return
    }

    let result = try adapter.akaChallenge(rand: rand, autn: autn)

    guard case .success(let res, let ik, let ck) = result.status else {
        Issue.record("Expected success AKA result")
        return
    }

    #expect(res.hexLowercase == vector.res.lowercased())
    #expect(ik.hexLowercase == vector.ik.lowercased())
    #expect(ck.hexLowercase == vector.ck.lowercased())
}

@Test func labSimRejectsUnknownChallenge() throws {
    let profile = try loadFixtureProfile()
    guard let labSim = profile.labSim else {
        Issue.record("Expected lab_sim in fixture profile")
        return
    }

    let adapter = LabSimAdapter(config: labSim)
    let rand = Data([0x01, 0x02, 0x03, 0x04])
    let autn = Data([0x05, 0x06, 0x07, 0x08])

    #expect(throws: SimAdapterError.unsupportedChallenge) {
        _ = try adapter.akaChallenge(rand: rand, autn: autn)
    }
}
