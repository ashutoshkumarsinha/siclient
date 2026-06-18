// ClientViewModelTests.swift
//
// Verifies the SwiftUI ClientViewModel that drives the GUI phone app: profile loading,
// registration, calls, hold/resume, DTMF, SMS, call forwarding, and emergency dialing.
// These tests use mock IMS transports so UI logic can be tested without a live network.

import Foundation
import Testing
import SICLientGUI

// MARK: - Initial state & profile loading

/// Before a profile is loaded the ViewModel must disable all IMS actions (register,
/// call, SMS, emergency) — matching the greyed-out buttons a user sees at launch.
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

/// Loading a lab profile from disk must populate the summary and enable registration,
/// just as when a user picks an operator JSON file in the GUI.
@MainActor
@Test func viewModelLoadProfileFromDisk() async throws {
    let model = ClientViewModel(profilePath: guiFixtureURL(named: "lab-volte-01.json").path)
    await model.loadProfile()
    #expect(!model.profileSummary.isEmpty)
    #expect(model.profileSummary.contains("lab-volte-01"))
    #expect(model.canRegister)
    #expect(model.connectionState == .idle)
}

// MARK: - Registration lifecycle

/// Register then deregister must transition idle → registered → idle, enabling and
/// disabling the corresponding toolbar buttons in the phone app.
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

// MARK: - Voice call control

/// Full MO call flow: register, place call, hold, resume, hang up — mirroring the
/// button sequence a user follows for a normal VoLTE voice call in the GUI.
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

/// DTMF can only be sent during an active call; the ViewModel must log the digit
/// sent for IVR/voicemail interaction testing from the GUI keypad.
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

// MARK: - SMS

/// SMS send requires registration and an enabled SMS service in the profile —
/// the GUI SMS panel must only activate when both conditions are met.
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

// MARK: - Supplementary services

/// Call forwarding (CFU) set/fetch via XCAP must work from the GUI supplementary
/// services panel after IMS registration.
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

// MARK: - Emergency calling

/// Emergency call button must connect immediately (even if registered) and return
/// to registered state after hang-up — matching E911 behavior in the phone app.
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

// MARK: - Button gating

/// After registration, Register is disabled and Deregister is enabled; Hang Up stays
/// disabled until a call is active — preventing invalid UI state combinations.
@MainActor
@Test func viewModelButtonGatingAfterRegistration() async throws {
    let profile = try loadGUIFixtureProfile()
    let model = try makeGUIViewModel(profile: profile)

    await model.register()
    #expect(!model.canRegister)
    #expect(model.canDeregister)
    #expect(!model.canHangUp)
}

// MARK: - UI accessibility

/// Every GUI control needs a unique accessibility identifier for UI automation and
/// VoiceOver — duplicates would break XCUITest scripts and screen reader navigation.
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
