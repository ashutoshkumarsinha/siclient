// ConfigTests.swift
//
// Verifies operator profile loading and validation — the JSON files that describe
// how a UE should reach the P-CSCF, which codecs to offer, and registration timers.
// Bad profiles must fail fast before any SIP REGISTER is sent to the network.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Profile loading

/// Loads the standard lab VoLTE fixture and checks core IMS fields (home domain,
/// static P-CSCF address, transport preference). This mirrors what happens when
/// the client reads an operator provisioning file at startup.
@Test func loadsLabProfile() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.profileID == "lab-volte-01")
    #expect(profile.homeDomain == "ims.mnc001.mcc001.3gppnetwork.org")
    #expect(profile.pcscf.address == "10.0.0.1")
    #expect(profile.transport.preference == [.udp, .tcp, .tls])
}

// MARK: - Profile validation

/// Static P-CSCF mode requires an explicit address; without one the client cannot
/// discover where to send the initial REGISTER.
@Test func rejectsStaticPCSCFWithoutAddress() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.address = nil

    #expect(throws: ProfileValidationError.staticPCSCFMissingAddress) {
        try ProfileValidator.validate(profile)
    }
}

/// Registration refresh ratio must stay within sane bounds (typically ~80% of Expires).
/// An invalid ratio would cause premature or endless re-REGISTER storms against the IMS.
@Test func rejectsInvalidRefreshRatio() throws {
    var profile = try loadFixtureProfile()
    profile.timers.registrationRefreshRatio = 0.05

    #expect(throws: ProfileValidationError.invalidRefreshRatio(0.05)) {
        try ProfileValidator.validate(profile)
    }
}

/// Missing profile files should surface a clear loader error rather than crashing
/// or attempting SIP with a blank configuration.
@Test func rejectsMissingProfileFile() {
    #expect(throws: ProfileLoaderError.self) {
        _ = try ProfileLoader.load(fromPath: "/tmp/does-not-exist-siclient.json")
    }
}
