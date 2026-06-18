import Foundation

public struct EmergencyConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var sosURI: String
    public var defaultNumber: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case sosURI = "sos_uri"
        case defaultNumber = "default_number"
    }

    public init(enabled: Bool = false, sosURI: String = "sip:sos", defaultNumber: String = "112") {
        self.enabled = enabled
        self.sosURI = sosURI
        self.defaultNumber = defaultNumber
    }
}

public struct SMSConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var smscURI: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case smscURI = "smsc_uri"
    }

    public init(enabled: Bool = false, smscURI: String = "sip:smsc@ims.example") {
        self.enabled = enabled
        self.smscURI = smscURI
    }
}

public struct SupplementaryConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var xcapRootURI: String
    public var auid: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case xcapRootURI = "xcap_root_uri"
        case auid
    }

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

public struct HandoverConfig: Codable, Sendable, Equatable {
    public var esrvccEnabled: Bool
    public var stirShakEnabled: Bool
    public var labIdentityHeader: String?

    enum CodingKeys: String, CodingKey {
        case esrvccEnabled = "esrvcc_enabled"
        case stirShakEnabled = "stir_shak_enabled"
        case labIdentityHeader = "lab_identity_header"
    }

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

public struct ServicesConfig: Codable, Sendable, Equatable {
    public var emergency: EmergencyConfig
    public var sms: SMSConfig
    public var supplementary: SupplementaryConfig
    public var handover: HandoverConfig

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
