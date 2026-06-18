import SwiftUI

public struct ContentView: View {
    @Bindable private var model: ClientViewModel

    public init(model: ClientViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            Form {
                Section("Profile") {
                    TextField("Profile path", text: $model.profilePath)
                        .accessibilityIdentifier(AccessibilityID.profilePathField)
                    Button("Load profile") {
                        Task { await model.loadProfile() }
                    }
                    .disabled(!model.canLoadProfile)
                    .accessibilityIdentifier(AccessibilityID.loadProfileButton)

                    if !model.profileSummary.isEmpty {
                        Text(model.profileSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Registration") {
                    Button("Register") {
                        Task { await model.register() }
                    }
                    .disabled(!model.canRegister)
                    .accessibilityIdentifier(AccessibilityID.registerButton)

                    Button("Deregister") {
                        Task { await model.deregister() }
                    }
                    .disabled(!model.canDeregister)
                    .accessibilityIdentifier(AccessibilityID.deregisterButton)
                }

                Section("Voice") {
                    TextField("Destination URI", text: $model.callDestination)
                        .accessibilityIdentifier(AccessibilityID.callDestinationField)
                    HStack {
                        Button("Call") {
                            Task { await model.placeCall() }
                        }
                        .disabled(!model.canPlaceCall)
                        .accessibilityIdentifier(AccessibilityID.placeCallButton)

                        Button("Hang up") {
                            Task { await model.hangUp() }
                        }
                        .disabled(!model.canHangUp)
                        .accessibilityIdentifier(AccessibilityID.hangUpButton)
                    }
                    HStack {
                        Button("Hold") {
                            Task { await model.hold() }
                        }
                        .disabled(!model.canHoldOrResume)
                        .accessibilityIdentifier(AccessibilityID.holdButton)

                        Button("Resume") {
                            Task { await model.resume() }
                        }
                        .disabled(!model.canHoldOrResume)
                        .accessibilityIdentifier(AccessibilityID.resumeButton)
                    }
                    HStack {
                        TextField("DTMF", text: $model.dtmfDigit)
                            .frame(width: 48)
                            .accessibilityIdentifier(AccessibilityID.dtmfField)
                        Button("Send") {
                            Task { await model.sendDTMF() }
                        }
                        .disabled(!model.canSendDTMF)
                        .accessibilityIdentifier(AccessibilityID.sendDTMFButton)
                    }
                }

                Section("SMS") {
                    TextField("Destination", text: $model.smsDestination)
                        .accessibilityIdentifier(AccessibilityID.smsDestinationField)
                    TextField("Message", text: $model.smsText)
                        .accessibilityIdentifier(AccessibilityID.smsTextField)
                    Button("Send SMS") {
                        Task { await model.sendSMS() }
                    }
                    .disabled(!model.canSendSMS)
                    .accessibilityIdentifier(AccessibilityID.sendSMSButton)
                }

                Section("Supplementary") {
                    TextField("CFU target", text: $model.callForwardingTarget)
                    HStack {
                        Button("Enable CFU") {
                            Task { await model.setCallForwarding() }
                        }
                        .disabled(!model.canSetForwarding)
                        Button("Fetch CFU") {
                            Task { await model.fetchCallForwarding() }
                        }
                        .disabled(!model.canFetchForwarding)
                        .accessibilityIdentifier(AccessibilityID.fetchForwardingButton)
                    }
                }

                Section("Emergency") {
                    Button("Emergency call (112)") {
                        Task { await model.placeEmergencyCall() }
                    }
                    .disabled(!model.canEmergencyCall)
                    .accessibilityIdentifier(AccessibilityID.emergencyCallButton)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("SICLient")
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusText)
                    .font(.headline)
                    .accessibilityIdentifier(AccessibilityID.statusLabel)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier(AccessibilityID.logView)
            }
            .padding()
        }
    }

    private var statusText: String {
        switch model.connectionState {
        case .idle:
            return model.profileSummary.isEmpty ? "Idle" : "Profile ready"
        case .bootstrapping:
            return "Registering…"
        case .registered:
            return "Registered"
        case .inCall:
            return "In call"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
