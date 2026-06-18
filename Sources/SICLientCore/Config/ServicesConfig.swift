import Foundation

// MARK: - File overview
//
// Optional IMS (IP Multimedia Subsystem) service settings loaded from the operator
// profile JSON: emergency calling, SMS (Short Message Service), supplementary
// services (XCAP), and handover features like eSRVCC.

/// Emergency call (SOS) configuration for IMS.
public struct EmergencyConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// SIP URI dialed for emergency sessions (e.g. sip:sos).
    public var sosURI: String
    /// Default emergency number (e.g. 112 in Europe).
    public var defaultNumber: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case sosURI = "sos_uri"
        case defaultNumber = "default_number"
    }

    /// Creates emergency settings with sensible defaults (disabled).
    public init(enabled: Bool = false, sosURI: String = "sip:sos", defaultNumber: String = "112") {
        self.enabled = enabled
        self.sosURI = sosURI
        self.defaultNumber = defaultNumber
    }
}

/// SMS-over-IMS configuration.
public struct SMSConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// SIP URI of the SMS Center (SMSC).
    public var smscURI: String
    /// Whether to wrap SMS in a 3GPP-specific SIP payload format.
    public var use3GPPPayload: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case smscURI = "smsc_uri"
        case use3GPPPayload = "use_3gpp_payload"
    }

    /// Creates SMS settings with defaults (disabled).
    public init(enabled: Bool = false, smscURI: String = "sip:smsc@ims.example", use3GPPPayload: Bool = false) {
        self.enabled = enabled
        self.smscURI = smscURI
        self.use3GPPPayload = use3GPPPayload
    }

    /// Decodes from JSON, defaulting use3GPPPayload to false when absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        smscURI = try container.decode(String.self, forKey: .smscURI)
        use3GPPPayload = try container.decodeIfPresent(Bool.self, forKey: .use3GPPPayload) ?? false
    }
}

/// Supplementary services (call forwarding, etc.) via XCAP (XML Configuration Access Protocol).
public struct SupplementaryConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Root URI for XCAP documents on the operator server.
    public var xcapRootURI: String
    /// Application Unique ID for the supplementary service document set.
    public var auid: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case xcapRootURI = "xcap_root_uri"
        case auid
    }

    /// Creates supplementary service settings with MMTel registration defaults.
    public init(
        enabled: Bool = false,
        xcapRootURI: String = "http://xcap.ims.example/xcap-root",
        auid: String = "org.3gpp.mmtel.registration"
    ) {
        self.enabled = enabled
        self.xcapRootURI = xcapRootURI
        self.auid = auid
    }
}

/// Handover and identity-related feature flags.
public struct HandoverConfig: Codable, Sendable, Equatable {
    /// eSRVCC (enhanced Single Radio Voice Call Continuity) — LTE to 2G/3G handover.
    public var esrvccEnabled: Bool
    /// STIR/SHAKEN caller-ID attestation for lab testing.
    public var stirShakEnabled: Bool
    /// Optional fixed Identity header value for lab STIR/SHAKEN tests.
    public var labIdentityHeader: String?

    enum CodingKeys: String, CodingKey {
        case esrvccEnabled = "esrvcc_enabled"
        case stirShakEnabled = "stir_shak_enabled"
        case labIdentityHeader = "lab_identity_header"
    }

    /// Creates handover settings with all features disabled by default.
    public init(
        esrvccEnabled: Bool = false,
        stirShakEnabled: Bool = false,
        labIdentityHeader: String? = nil
    ) {
        self.esrvccEnabled = esrvccEnabled
        self.stirShakEnabled = stirShakEnabled
        self.labIdentityHeader = labIdentityHeader
    }
}

/// Groups all optional IMS service configurations from the operator profile.
public struct ServicesConfig: Codable, Sendable, Equatable {
    public var emergency: EmergencyConfig
    public var sms: SMSConfig
    public var supplementary: SupplementaryConfig
    public var handover: HandoverConfig

    /// Creates a services block with all sub-configs at their defaults.
    public init(
        emergency: EmergencyConfig = EmergencyConfig(),
        sms: SMSConfig = SMSConfig(),
        supplementary: SupplementaryConfig = SupplementaryConfig(),
        handover: HandoverConfig = HandoverConfig()
    ) {
        self.emergency = emergency
        self.sms = sms
        self.supplementary = supplementary
        self.handover = handover
    }
}
