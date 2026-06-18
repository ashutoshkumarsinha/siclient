import Foundation

public enum TransportProtocol: String, Codable, Sendable, CaseIterable {
    case udp
    case tcp
    case tls
}

public enum PCSCFDiscoveryMode: String, Codable, Sendable {
    case `static`
    case pco
    case dhcp
}

public enum SecurityMechanism: String, Codable, Sendable {
    case ipsec3gpp = "ipsec-3gpp"
    case tls
}

public struct PCSCFConfig: Codable, Sendable, Equatable {
    public var mode: PCSCFDiscoveryMode
    public var address: String?
    public var port: Int?
    /// DNS domain for NAPTR/SRV P-CSCF discovery (defaults to home_domain).
    public var dnsDomain: String?
    /// Static PCO-provided P-CSCF list (host:port) for lab/production bridge.
    public var pcoAddresses: [String]?
    /// DHCP option 120 / IMS P-CSCF list for lab bridge.
    public var dhcpAddresses: [String]?

    enum CodingKeys: String, CodingKey {
        case mode
        case address
        case port
        case dnsDomain = "dns_domain"
        case pcoAddresses = "pco_addresses"
        case dhcpAddresses = "dhcp_addresses"
    }

    public init(
        mode: PCSCFDiscoveryMode,
        address: String? = nil,
        port: Int? = nil,
        dnsDomain: String? = nil,
        pcoAddresses: [String]? = nil,
        dhcpAddresses: [String]? = nil
    ) {
        self.mode = mode
        self.address = address
        self.port = port
        self.dnsDomain = dnsDomain
        self.pcoAddresses = pcoAddresses
        self.dhcpAddresses = dhcpAddresses
    }
}

public struct TransportConfig: Codable, Sendable, Equatable {
    public var preference: [TransportProtocol]

    public init(preference: [TransportProtocol]) {
        self.preference = preference
    }
}

public struct SecurityConfig: Codable, Sendable, Equatable {
    public var mechanism: SecurityMechanism
    public var tls: TLSConfig

    enum CodingKeys: String, CodingKey {
        case mechanism
        case tls
    }

    public init(mechanism: SecurityMechanism, tls: TLSConfig = TLSConfig()) {
        self.mechanism = mechanism
        self.tls = tls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mechanism = try container.decode(SecurityMechanism.self, forKey: .mechanism)
        tls = try container.decodeIfPresent(TLSConfig.self, forKey: .tls) ?? TLSConfig()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mechanism, forKey: .mechanism)
        try container.encode(tls, forKey: .tls)
    }
}

public struct TLSConfig: Codable, Sendable, Equatable {
    /// SHA-256 fingerprints of trusted server certificates (hex, lowercase, no colons).
    public var pinnedCertificateSHA256: [String]
    /// Skip certificate validation (lab/mock P-CSCF only).
    public var allowInsecureLab: Bool

    enum CodingKeys: String, CodingKey {
        case pinnedCertificateSHA256 = "pinned_cert_sha256"
        case allowInsecureLab = "allow_insecure_lab"
    }

    public init(pinnedCertificateSHA256: [String] = [], allowInsecureLab: Bool = true) {
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
        self.allowInsecureLab = allowInsecureLab
    }
}

public struct CodecConfig: Codable, Sendable, Equatable {
    public var audio: [String]
    public var video: [String]

    public init(audio: [String] = ["AMR-WB", "AMR"], video: [String] = ["H264", "H265"]) {
        self.audio = audio
        self.video = video
    }
}

public struct PreconditionsConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var failTimeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case failTimeoutMs = "fail_timeout_ms"
    }

    public init(enabled: Bool = true, failTimeoutMs: Int = 8000) {
        self.enabled = enabled
        self.failTimeoutMs = failTimeoutMs
    }
}

public struct TimersConfig: Codable, Sendable, Equatable {
    public var registrationRefreshRatio: Double
    public var keepaliveSec: Int

    enum CodingKeys: String, CodingKey {
        case registrationRefreshRatio = "registration_refresh_ratio"
        case keepaliveSec = "keepalive_sec"
    }

    public init(registrationRefreshRatio: Double = 0.8, keepaliveSec: Int = 45) {
        self.registrationRefreshRatio = registrationRefreshRatio
        self.keepaliveSec = keepaliveSec
    }
}

public struct AKAVector: Codable, Sendable, Equatable {
    public var rand: String
    public var autn: String
    public var res: String
    public var ik: String
    public var ck: String
    public var auts: String?

    public init(rand: String, autn: String, res: String, ik: String, ck: String, auts: String? = nil) {
        self.rand = rand
        self.autn = autn
        self.res = res
        self.ik = ik
        self.ck = ck
        self.auts = auts
    }
}

public struct LabSimConfig: Codable, Sendable, Equatable {
    public var impi: String
    public var impus: [String]
    public var akaVectors: [AKAVector]

    enum CodingKeys: String, CodingKey {
        case impi
        case impus
        case akaVectors = "aka_vectors"
    }

    public init(impi: String, impus: [String], akaVectors: [AKAVector] = []) {
        self.impi = impi
        self.impus = impus
        self.akaVectors = akaVectors
    }
}

public struct OperatorProfile: Codable, Sendable, Equatable {
    public var profileID: String
    public var homeDomain: String
    public var pcscf: PCSCFConfig
    public var transport: TransportConfig
    public var security: SecurityConfig
    public var codecs: CodecConfig
    public var preconditions: PreconditionsConfig
    public var timers: TimersConfig
    public var media: MediaConfig
    public var resilience: ResilienceConfig
    public var services: ServicesConfig
    public var labSim: LabSimConfig?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case homeDomain = "home_domain"
        case pcscf
        case transport
        case security
        case codecs
        case preconditions
        case timers
        case media
        case resilience
        case services
        case labSim = "lab_sim"
    }

    public init(
        profileID: String,
        homeDomain: String,
        pcscf: PCSCFConfig,
        transport: TransportConfig,
        security: SecurityConfig,
        codecs: CodecConfig = CodecConfig(),
        preconditions: PreconditionsConfig = PreconditionsConfig(),
        timers: TimersConfig = TimersConfig(),
        media: MediaConfig = MediaConfig(),
        resilience: ResilienceConfig = ResilienceConfig(),
        services: ServicesConfig = ServicesConfig(),
        labSim: LabSimConfig? = nil
    ) {
        self.profileID = profileID
        self.homeDomain = homeDomain
        self.pcscf = pcscf
        self.transport = transport
        self.security = security
        self.codecs = codecs
        self.preconditions = preconditions
        self.timers = timers
        self.media = media
        self.resilience = resilience
        self.services = services
        self.labSim = labSim
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileID = try container.decode(String.self, forKey: .profileID)
        homeDomain = try container.decode(String.self, forKey: .homeDomain)
        pcscf = try container.decode(PCSCFConfig.self, forKey: .pcscf)
        transport = try container.decode(TransportConfig.self, forKey: .transport)
        security = try container.decode(SecurityConfig.self, forKey: .security)
        codecs = try container.decodeIfPresent(CodecConfig.self, forKey: .codecs) ?? CodecConfig()
        preconditions = try container.decodeIfPresent(PreconditionsConfig.self, forKey: .preconditions) ?? PreconditionsConfig()
        timers = try container.decodeIfPresent(TimersConfig.self, forKey: .timers) ?? TimersConfig()
        media = try container.decodeIfPresent(MediaConfig.self, forKey: .media) ?? MediaConfig()
        resilience = try container.decodeIfPresent(ResilienceConfig.self, forKey: .resilience) ?? ResilienceConfig()
        services = try container.decodeIfPresent(ServicesConfig.self, forKey: .services) ?? ServicesConfig()
        labSim = try container.decodeIfPresent(LabSimConfig.self, forKey: .labSim)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(homeDomain, forKey: .homeDomain)
        try container.encode(pcscf, forKey: .pcscf)
        try container.encode(transport, forKey: .transport)
        try container.encode(security, forKey: .security)
        try container.encode(codecs, forKey: .codecs)
        try container.encode(preconditions, forKey: .preconditions)
        try container.encode(timers, forKey: .timers)
        try container.encode(media, forKey: .media)
        try container.encode(resilience, forKey: .resilience)
        try container.encode(services, forKey: .services)
        try container.encodeIfPresent(labSim, forKey: .labSim)
    }
}
