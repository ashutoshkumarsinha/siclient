import Foundation
import Testing
import SICLientGUI

@MainActor
@Test func viewModelInitialStateGatesActions() {
    let model = ClientViewModel()
    #expect(model.connectionState == .idle)
    #expect(!model.canRegister)
    #expect(!model.canPlaceCall)
    #expect(!model.canHangUp)
    #expect(!model.canSendSMS)
    #expect(!model.canEmergencyCall)
}

@MainActor
@Test func viewModelLoadProfileFromDisk() async throws {
    let model = ClientViewModel(profilePath: guiFixtureURL(named: "lab-volte-01.json").path)
    await model.loadProfile()
    #expect(!model.profileSummary.isEmpty)
    #expect(model.profileSummary.contains("lab-volte-01"))
    #expect(model.canRegister)
    #expect(model.connectionState == .idle)
}

@MainActor
@Test func viewModelRegisterAndDeregister() async throws {
    let profile = try loadGUIFixtureProfile()
    let model = try makeGUIViewModel(profile: profile)

    await model.register()
    #expect(model.connectionState == .registered)
    #expect(model.canPlaceCall == false) // no destination yet
    #expect(model.canDeregister)

    await model.deregister()
    #expect(model.connectionState == .idle)
}

@MainActor
@Test func viewModelPlaceCallHoldResumeHangUp() async throws {
    let profile = try loadGUIFixtureProfile()
    let model = try makeGUIViewModel(profile: profile)
    model.callDestination = "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org"

    await model.register()
    #expect(model.canPlaceCall)

    await model.placeCall()
    #expect(model.connectionState == .inCall)
    #expect(model.canHangUp)
    #expect(!model.canPlaceCall)

    await model.hold()
    #expect(model.logLines.contains { $0.contains("Call held") })

    await model.resume()
    #expect(model.logLines.contains { $0.contains("Call resumed") })

    await model.hangUp()
    #expect(model.connectionState == .registered)
    #expect(model.logLines.contains { $0.contains("Call ended") })
}

@MainActor
@Test func viewModelSendDTMFDuringCall() async throws {
    let profile = try loadGUIFixtureProfile()
    let model = try makeGUIViewModel(profile: profile)
    model.callDestination = "sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org"

    await model.register()
    await model.placeCall()
    model.dtmfDigit = "5"
    #expect(model.canSendDTMF)

    await model.sendDTMF()
    #expect(model.logLines.contains { $0.contains("DTMF sent: 5") })
}

@MainActor
@Test func viewModelSendSMSWhenRegistered() async throws {
    var profile = try loadGUIFixtureProfile()
    profile.services.sms.enabled = true
    let model = try makeGUIViewModel(profile: profile)
    model.smsDestination = "tel:+15551212"
    model.smsText = "GUI test SMS"

    await model.register()
    #expect(model.canSendSMS)

    await model.sendSMS()
    #expect(model.logLines.contains { $0.contains("SMS sent") })
}

@MainActor
@Test func viewModelCallForwardingControls() async throws {
    var profile = try loadGUIFixtureProfile()
    profile.services.supplementary.enabled = true
    let model = try makeGUIViewModel(profile: profile)
    model.callForwardingTarget = "tel:+15559876"

    await model.register()
    #expect(model.canFetchForwarding)
    #expect(model.canSetForwarding)

    await model.setCallForwarding()
    #expect(model.logLines.contains { $0.contains("CFU enabled") })

    await model.fetchCallForwarding()
    #expect(model.logLines.contains { $0.contains("CFU active=") })
}

@MainActor
@Test func viewModelEmergencyCallFlow() async throws {
    var profile = try loadGUIFixtureProfile()
    profile.services.emergency.enabled = true
    let model = try makeGUIViewModel(profile: profile)

    #expect(model.canEmergencyCall)
    await model.placeEmergencyCall()
    #expect(model.connectionState == .inCall)
    #expect(model.logLines.contains { $0.contains("Emergency call connected") })

    await model.hangUp()
    #expect(model.connectionState == .registered)
}

@MainActor
@Test func viewModelButtonGatingAfterRegistration() async throws {
    let profile = try loadGUIFixtureProfile()
    let model = try makeGUIViewModel(profile: profile)

    await model.register()
    #expect(!model.canRegister)
    #expect(model.canDeregister)
    #expect(!model.canHangUp)
}

@Test func accessibilityIdentifiersAreUniqueAndNonEmpty() {
    let ids = [
        AccessibilityID.profilePathField,
        AccessibilityID.loadProfileButton,
        AccessibilityID.registerButton,
        AccessibilityID.deregisterButton,
        AccessibilityID.callDestinationField,
        AccessibilityID.placeCallButton,
        AccessibilityID.hangUpButton,
        AccessibilityID.holdButton,
        AccessibilityID.resumeButton,
        AccessibilityID.dtmfField,
        AccessibilityID.sendDTMFButton,
        AccessibilityID.smsDestinationField,
        AccessibilityID.smsTextField,
        AccessibilityID.sendSMSButton,
        AccessibilityID.emergencyCallButton,
        AccessibilityID.fetchForwardingButton,
        AccessibilityID.statusLabel,
        AccessibilityID.logView,
    ]
    #expect(Set(ids).count == ids.count)
    #expect(ids.allSatisfy { !$0.isEmpty && $0.hasPrefix("gui.") })
}
