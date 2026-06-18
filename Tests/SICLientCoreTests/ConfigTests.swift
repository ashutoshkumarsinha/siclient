import Foundation
import Testing
@testable import SICLientCore

@Test func loadsLabProfile() throws {
    let profile = try loadFixtureProfile()
    #expect(profile.profileID == "lab-volte-01")
    #expect(profile.homeDomain == "ims.mnc001.mcc001.3gppnetwork.org")
    #expect(profile.pcscf.address == "10.0.0.1")
    #expect(profile.transport.preference == [.udp, .tcp, .tls])
}

@Test func rejectsStaticPCSCFWithoutAddress() throws {
    var profile = try loadFixtureProfile()
    profile.pcscf.address = nil

    #expect(throws: ProfileValidationError.staticPCSCFMissingAddress) {
        try ProfileValidator.validate(profile)
    }
}

@Test func rejectsInvalidRefreshRatio() throws {
    var profile = try loadFixtureProfile()
    profile.timers.registrationRefreshRatio = 0.05

    #expect(throws: ProfileValidationError.invalidRefreshRatio(0.05)) {
        try ProfileValidator.validate(profile)
    }
}

@Test func rejectsMissingProfileFile() {
    #expect(throws: ProfileLoaderError.self) {
        _ = try ProfileLoader.load(fromPath: "/tmp/does-not-exist-siclient.json")
    }
}
