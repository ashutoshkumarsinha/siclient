import Foundation

// MARK: - File Overview
//
// Application is the programmatic entry point used by the CLI and tests. It loads
// the operator profile, discovers the P-CSCF (Proxy Call Session Control Function),
// creates CallService, and runs the requested flow (register, call, SMS, etc.).

/// Command-line and runtime options for a single Application run.
public struct ApplicationOptions: Sendable {
    public let profilePath: String
    public let dryRun: Bool
    public let deregister: Bool
    public let moCallDestination: String?
    public let callDurationSec: Int
    public let holdAfterConnect: Bool
    public let dtmfDigit: Character?
    public let emergencyCall: Bool
    public let emergencyDestination: String?
    public let smsDestination: String?
    public let smsText: String?
    public let fetchCallForwarding: Bool
    public let setCallForwardingTarget: String?

    /// Creates runtime options from CLI flags or programmatic configuration.
    public init(
        profilePath: String,
        dryRun: Bool,
        deregister: Bool = false,
        moCallDestination: String? = nil,
        callDurationSec: Int = 2,
        holdAfterConnect: Bool = false,
        dtmfDigit: Character? = nil,
        emergencyCall: Bool = false,
        emergencyDestination: String? = nil,
        smsDestination: String? = nil,
        smsText: String? = nil,
        fetchCallForwarding: Bool = false,
        setCallForwardingTarget: String? = nil
    ) {
        self.profilePath = profilePath
        self.dryRun = dryRun
        self.deregister = deregister
        self.moCallDestination = moCallDestination
        self.callDurationSec = callDurationSec
        self.holdAfterConnect = holdAfterConnect
        self.dtmfDigit = dtmfDigit
        self.emergencyCall = emergencyCall
        self.emergencyDestination = emergencyDestination
        self.smsDestination = smsDestination
        self.smsText = smsText
        self.fetchCallForwarding = fetchCallForwarding
        self.setCallForwardingTarget = setCallForwardingTarget
    }
}

/// Errors during application bootstrap (profile load, adapter setup).
public enum ApplicationError: Error, Sendable, CustomStringConvertible {
    case bootstrapFailed(String)

    public var description: String {
        switch self {
        case .bootstrapFailed(let reason):
            return reason
        }
    }
}

/// Orchestrates profile loading, IMS bootstrap, and the selected signaling flow.
public struct Application: Sendable {
    private let options: ApplicationOptions
    private let output: @Sendable (String) -> Void

    /// Creates an application with options and an optional log output sink.
    public init(options: ApplicationOptions, output: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.options = options
        self.output = output
    }

    /// Loads profile, connects to P-CSCF, and executes the flow implied by options.
    public func run() async throws {
        let logger = Logger(
            correlationID: CorrelationID(prefix: options.deregister ? "dereg" : "bootstrap"),
            minimumLevel: .info,
            output: output
        )

        let profile = try ProfileLoader.load(fromPath: options.profilePath)
        let platform = try PlatformContext.stubbed(profile: profile)

        let impi = try platform.sim.getIMPI()
        let impus = try platform.sim.getIMPUList()
        // Discover P-CSCF — first SIP hop in the IMS network for this operator.
        let pcscf = try platform.network.discoverPCSCF(profile: profile)
        let access = try platform.accessInfo.currentAccessInfo()

        logger.info(
            "SICLient bootstrap complete",
            fields: [
                "profile_id": profile.profileID,
                "home_domain": profile.homeDomain,
                "impi": impi,
                "impu_count": String(impus.count),
                "default_impu": impus.first ?? "",
                "pcscf": "\(pcscf.host):\(pcscf.port)",
                "transport": pcscf.transport.rawValue,
                "security": profile.security.mechanism.rawValue,
                "pani": access.paniHeaderValue,
                "dry_run": String(options.dryRun),
                "rtp_transport": profile.media.rtpTransport.rawValue,
                "audio_io": String(profile.media.enableAudioIO),
            ]
        )

        if options.dryRun {
            logger.info("Dry run finished; no signaling started")
            return
        }

        let transport = TransportFactory.make(endpoint: pcscf, profile: profile)
        let service = CallService(profile: profile, platform: platform, transport: transport, logger: logger)

        if options.deregister {
            try await service.register()
            try await service.deregister()
            return
        }

        try await service.register()

        if options.fetchCallForwarding || options.setCallForwardingTarget != nil {
            if let target = options.setCallForwardingTarget {
                try await service.setCallForwarding(active: true, target: target)
                logger.info("Call forwarding enabled", fields: ["target": target])
            }
            if options.fetchCallForwarding || options.setCallForwardingTarget != nil {
                let rule = try await service.fetchCallForwarding()
                logger.info(
                    "Call forwarding status",
                    fields: ["active": String(rule.active), "target": rule.target ?? ""]
                )
            }
            return
        }

        if let smsDestination = options.smsDestination, let smsText = options.smsText {
            try await service.sendSMS(to: smsDestination, text: smsText)
            logger.info("SMS flow complete", fields: ["destination": smsDestination])
            return
        }

        if options.emergencyCall {
            let emergencyContext = try await service.registerEmergency()
            let session = try await service.placeEmergencyCall(
                to: options.emergencyDestination,
                registration: emergencyContext
            )
            logger.info(
                "Emergency call established",
                fields: [
                    "destination": session.remoteURI,
                    "codec": session.negotiatedCodec?.rawValue ?? "",
                ]
            )
            try await Task.sleep(for: .seconds(options.callDurationSec))
            try await service.hangUp()
            logger.info("Emergency call flow complete", fields: [:])
            return
        }

        if let destination = options.moCallDestination {
            let session = try await service.placeCall(to: destination)
            logger.info(
                "MO call established",
                fields: [
                    "destination": destination,
                    "codec": session.negotiatedCodec?.rawValue ?? "",
                    "preconditions_met": String(session.preconditionState.allMet),
                    "remote_media": session.remoteMedia.map { "\($0.address):\($0.port)" } ?? "",
                ]
            )

            if options.holdAfterConnect {
                try await service.hold()
                logger.info("Call held", fields: [:])
                try await Task.sleep(for: .milliseconds(500))
                try await service.resume()
                logger.info("Call resumed", fields: [:])
            }

            if let digit = options.dtmfDigit {
                try await service.sendDTMF(digit)
                logger.info("DTMF sent", fields: ["digit": String(digit)])
            }

            let stats = await service.mediaStats()
            logger.info(
                "Media stats",
                fields: [
                    "packets_sent": String(stats.packetsSent),
                    "packets_received": String(stats.packetsReceived),
                    "packets_lost": String(stats.packetsLost),
                    "jitter_ms": String(format: "%.2f", stats.jitterMs),
                ]
            )

            try await Task.sleep(for: .seconds(options.callDurationSec))
            try await service.hangUp()
            logger.info("MO call flow complete", fields: ["destination": destination])
            return
        }

        logger.info("Registration flow complete; client is registered")
    }
}
