// LabSimAdapterTests.swift
//
// Verifies the lab SIM adapter that emulates USIM AKA authentication without real
// hardware. In IMS, every REGISTER challenge (RAND/AUTN from the P-CSCF) must be
// answered with RES/IK/CK from the SIM — these tests use preloaded test vectors.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - AKA vector lookup

/// When the P-CSCF sends a known RAND/AUTN pair from the lab profile, the adapter
/// must return the matching RES, IK, and CK so Digest authentication succeeds.
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

/// Unknown RAND/AUTN pairs (not in the test vector table) should fail cleanly,
/// just as a real SIM would reject an invalid network challenge.
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
