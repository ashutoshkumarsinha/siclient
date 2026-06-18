import Foundation
import Observation
import SICLientCore

// MARK: - File Overview
// SwiftUI view model that drives the SICLient GUI: loads profiles, registers with IMS,
// places calls, sends SMS, and manages supplementary services. Bridges UI actions to
// the underlying CallService.

/// High-level connection state shown in the GUI status area.
public enum ClientConnectionState: Equatable, Sendable {
    case idle
    case bootstrapping
    case registered
    case inCall
    case error(String)
}

/// Main view model for the SICLient desktop GUI; owns profile, call service, and log state.
@MainActor
@Observable
public final class ClientViewModel {
    public private(set) var connectionState: ClientConnectionState = .idle
    public private(set) var logLines: [String] = []
    public private(set) var profileSummary: String = ""
    public private(set) var isBusy = false

    public var profilePath: String
    public var callDestination: String
    public var smsDestination: String
    public var smsText: String
    public var dtmfDigit: String
    public var callForwardingTarget: String

    private var loadedProfile: OperatorProfile?
    private var callService: CallService?

    /// Creates a view model with an empty profile path and default field values.
    public init(profilePath: String = "") {
        self.profilePath = profilePath
        self.callDestination = ""
        self.smsDestination = ""
        self.smsText = ""
        self.dtmfDigit = ""
        self.callForwardingTarget = ""
    }

    /// Lab / test injection — bypasses filesystem and network discovery.
    public init(profile: OperatorProfile, callService: CallService, profilePath: String = "lab-profile") {
        self.profilePath = profilePath
        self.callDestination = ""
        self.smsDestination = ""
        self.smsText = ""
        self.dtmfDigit = ""
        self.callForwardingTarget = ""
        self.loadedProfile = profile
        self.callService = callService
        self.profileSummary = Self.summarize(profile)
    }

    /// True when a profile path is entered and no operation is in progress.
    public var canLoadProfile: Bool {
        !isBusy && !profilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when a profile is loaded and the client is not already registered or busy.
    public var canRegister: Bool {
        loadedProfile != nil && !isBusy && connectionState != .registered && connectionState != .inCall
            && connectionState != .bootstrapping
    }

    /// True when registered or in a call and deregistration is allowed.
    public var canDeregister: Bool {
        loadedProfile != nil && !isBusy && (connectionState == .registered || connectionState == .inCall)
    }

    /// True when registered and a call destination is entered.
    public var canPlaceCall: Bool {
        connectionState == .registered && !isBusy && !callDestination.isEmpty
    }

    /// True when currently in an active call.
    public var canHangUp: Bool {
        connectionState == .inCall && !isBusy
    }

    /// True when in a call and hold/resume is available.
    public var canHoldOrResume: Bool {
        connectionState == .inCall && !isBusy
    }

    /// True when in a call and exactly one DTMF digit is entered.
    public var canSendDTMF: Bool {
        connectionState == .inCall && !isBusy && dtmfDigit.count == 1
    }

    /// True when registered with SMS destination and message text filled in.
    public var canSendSMS: Bool {
        connectionState == .registered && !isBusy && !smsDestination.isEmpty && !smsText.isEmpty
    }

    /// True when an emergency call can be placed (profile loaded, not already in call).
    public var canEmergencyCall: Bool {
        loadedProfile != nil && !isBusy && connectionState != .inCall && connectionState != .bootstrapping
    }

    /// True when registered and call forwarding can be fetched via XCAP.
    public var canFetchForwarding: Bool {
        connectionState == .registered && !isBusy
    }

    /// True when registered and a CFU target URI is entered.
    public var canSetForwarding: Bool {
        connectionState == .registered && !isBusy && !callForwardingTarget.isEmpty
    }

    /// Loads an operator profile from `profilePath` on disk.
    public func loadProfile() async {
        guard canLoadProfile else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let profile = try ProfileLoader.load(fromPath: profilePath)
            loadedProfile = profile
            profileSummary = Self.summarize(profile)
            connectionState = .idle
            appendLog("Profile loaded: \(profile.profileID)")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Profile load failed: \(error)")
        }
    }

    /// Registers with IMS (IP Multimedia Subsystem), creating CallService on first use.
    public func register() async {
        guard canRegister, let profile = loadedProfile else { return }
        isBusy = true
        connectionState = .bootstrapping
        defer { isBusy = false }

        do {
            if callService == nil {
                let logger = Logger(output: { [weak self] line in
                    Task { @MainActor in self?.appendLog(line) }
                })
                let platform = try PlatformContext.stubbed(profile: profile)
                let pcscf = try platform.network.discoverPCSCF(profile: profile)
                let sipTransport = TransportFactory.make(endpoint: pcscf, profile: profile)
                callService = CallService(
                    profile: profile,
                    platform: platform,
                    transport: sipTransport,
                    logger: logger,
                    enableMedia: false
                )
            }
            try await callService?.register()
            connectionState = .registered
            appendLog("Registered")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Register failed: \(error)")
        }
    }

    /// Hangs up any active call and deregisters from IMS.
    public func deregister() async {
        guard canDeregister, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            if connectionState == .inCall {
                try await callService.hangUp()
            }
            try await callService.deregister()
            connectionState = .idle
            appendLog("Deregistered")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Deregister failed: \(error)")
        }
    }

    /// Places a voice call to `callDestination`.
    public func placeCall() async {
        guard canPlaceCall, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await callService.placeCall(to: callDestination)
            connectionState = .inCall
            appendLog("Call connected to \(callDestination)")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Call failed: \(error)")
        }
    }

    /// Ends the current call and returns to registered state.
    public func hangUp() async {
        guard canHangUp, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.hangUp()
            connectionState = .registered
            appendLog("Call ended")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Hang up failed: \(error)")
        }
    }

    /// Puts the active call on hold.
    public func hold() async {
        guard canHoldOrResume, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.hold()
            appendLog("Call held")
        } catch {
            appendLog("Hold failed: \(error)")
        }
    }

    /// Resumes a held call.
    public func resume() async {
        guard canHoldOrResume, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.resume()
            appendLog("Call resumed")
        } catch {
            appendLog("Resume failed: \(error)")
        }
    }

    /// Sends one DTMF (Dual-Tone Multi-Frequency) digit during an active call.
    public func sendDTMF() async {
        guard canSendDTMF, let callService, let digit = dtmfDigit.first else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.sendDTMF(digit)
            appendLog("DTMF sent: \(digit)")
        } catch {
            appendLog("DTMF failed: \(error)")
        }
    }

    /// Sends an SMS (Short Message Service) to `smsDestination`.
    public func sendSMS() async {
        guard canSendSMS, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.sendSMS(to: smsDestination, text: smsText)
            appendLog("SMS sent to \(smsDestination)")
        } catch {
            appendLog("SMS failed: \(error)")
        }
    }

    /// Registers if needed and places an emergency call to 112.
    public func placeEmergencyCall() async {
        guard canEmergencyCall, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            if connectionState != .registered {
                try await callService.register()
                connectionState = .registered
            }
            _ = try await callService.placeEmergencyCall(to: "tel:112")
            connectionState = .inCall
            appendLog("Emergency call connected")
        } catch {
            connectionState = .error(error.localizedDescription)
            appendLog("Emergency call failed: \(error)")
        }
    }

    /// Fetches call forwarding unconditional (CFU) settings via XCAP.
    public func fetchCallForwarding() async {
        guard canFetchForwarding, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let rule = try await callService.fetchCallForwarding()
            appendLog("CFU active=\(rule.active) target=\(rule.target ?? "")")
        } catch {
            appendLog("Fetch CFU failed: \(error)")
        }
    }

    /// Enables call forwarding unconditional to `callForwardingTarget`.
    public func setCallForwarding() async {
        guard canSetForwarding, let callService else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await callService.setCallForwarding(active: true, target: callForwardingTarget)
            appendLog("CFU enabled to \(callForwardingTarget)")
        } catch {
            appendLog("Set CFU failed: \(error)")
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
    }

    private static func summarize(_ profile: OperatorProfile) -> String {
        "\(profile.profileID) · \(profile.homeDomain) · \(profile.security.mechanism.rawValue)"
    }
}
