import Foundation

// MARK: - File overview
//
// The central configuration model for an IMS (IP Multimedia Subsystem) client.
// An operator profile (JSON file) tells the client how to reach the P-CSCF
// (Proxy Call Session Control Function), which SIP (Session Initiation Protocol)
// transports and security to use, which codecs to offer, and optional lab SIM
// credentials for testing.

/// SIP transport protocols in priority order (UDP, TCP, or TLS).
public enum TransportProtocol: String, Codable, Sendable, CaseIterable {
    case udp
    case tcp
    case tls
}

/// How the client learns the P-CSCF address.
public enum PCSCFDiscoveryMode: String, Codable, Sendable {
    /// Fixed host/port in the profile.
    case `static`
    /// Addresses from modem PCO (Protocol Configuration Options).
    case pco
    /// Addresses from DHCP (Dynamic Host Configuration Protocol) option 120.
    case dhcp
}

/// Post-registration security mechanism between UE and P-CSCF.
public enum SecurityMechanism: String, Codable, Sendable {
  /// 3GPP IPsec (IP Security) on dedicated ports.
    case ipsec3gpp = "ipsec-3gpp"
    /// TLS (Transport Layer Security) on a dedicated port.
    case tls
}

/// P-CSCF discovery and addressing settings from the operator profile.
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

    /// Creates P-CSCF config for the chosen discovery mode.
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

/// Ordered list of preferred SIP transport protocols.
public struct TransportConfig: Codable, Sendable, Equatable {
    public var preference: [TransportProtocol]

    /// Creates transport preferences (first entry is tried first).
    public init(preference: [TransportProtocol]) {
        self.preference = preference
    }
}

/// Security mechanism and TLS settings for SIP signaling.
public struct SecurityConfig: Codable, Sendable, Equatable {
    public var mechanism: SecurityMechanism
    public var tls: TLSConfig

    enum CodingKeys: String, CodingKey {
        case mechanism
        case tls
    }

    /// Creates security config with optional TLS sub-settings.
    public init(mechanism: SecurityMechanism, tls: TLSConfig = TLSConfig()) {
        self.mechanism = mechanism
        self.tls = tls
    }

    /// Decodes from JSON, defaulting TLS config when absent.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mechanism = try container.decode(SecurityMechanism.self, forKey: .mechanism)
        tls = try container.decodeIfPresent(TLSConfig.self, forKey: .tls) ?? TLSConfig()
    }

    /// Encodes mechanism and TLS settings to JSON.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mechanism, forKey: .mechanism)
        try container.encode(tls, forKey: .tls)
    }
}

/// TLS certificate pinning and lab-trust options.
public struct TLSConfig: Codable, Sendable, Equatable {
    /// SHA-256 fingerprints of trusted server certificates (hex, lowercase, no colons).
    public var pinnedCertificateSHA256: [String]
    /// Skip certificate validation (lab/mock P-CSCF only).
    public var allowInsecureLab: Bool

    enum CodingKeys: String, CodingKey {
        case pinnedCertificateSHA256 = "pinned_cert_sha256"
        case allowInsecureLab = "allow_insecure_lab"
    }

    /// Creates TLS config; lab mode allows insecure certs by default.
    public init(pinnedCertificateSHA256: [String] = [], allowInsecureLab: Bool = true) {
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
        self.allowInsecureLab = allowInsecureLab
    }
}

/// Preferred audio and video codec names for SDP (Session Description Protocol).
public struct CodecConfig: Codable, Sendable, Equatable {
    public var audio: [String]
    public var video: [String]

    /// Creates codec lists with typical VoLTE defaults (AMR-WB, H.264).
    public init(audio: [String] = ["AMR-WB", "AMR"], video: [String] = ["H264", "H265"]) {
        self.audio = audio
        self.video = video
    }
}

/// Resource reservation precondition settings for VoLTE setup.
public struct PreconditionsConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Milliseconds to wait for preconditions before failing the call.
    public var failTimeoutMs: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case failTimeoutMs = "fail_timeout_ms"
    }

    /// Creates precondition config (enabled by default, 8 s timeout).
    public init(enabled: Bool = true, failTimeoutMs: Int = 8000) {
        self.enabled = enabled
        self.failTimeoutMs = failTimeoutMs
    }
}

/// SIP registration refresh and keepalive timing.
public struct TimersConfig: Codable, Sendable, Equatable {
    /// Fraction of Expires at which to re-REGISTER (e.g. 0.8 = 80%).
    public var registrationRefreshRatio: Double
    /// Seconds between SIP keepalive messages on idle connections.
    public var keepaliveSec: Int

    enum CodingKeys: String, CodingKey {
        case registrationRefreshRatio = "registration_refresh_ratio"
        case keepaliveSec = "keepalive_sec"
    }

    /// Creates timer defaults (refresh at 80% of Expires, 45 s keepalive).
    public init(registrationRefreshRatio: Double = 0.8, keepaliveSec: Int = 45) {
        self.registrationRefreshRatio = registrationRefreshRatio
        self.keepaliveSec = keepaliveSec
    }
}

/// One pre-computed AKA (Authentication and Key Agreement) test vector for lab SIM.
public struct AKAVector: Codable, Sendable, Equatable {
    public var rand: String
    public var autn: String
    public var res: String
    public var ik: String
    public var ck: String
    /// Present only for sync-failure test scenarios (AUTS value).
    public var auts: String?

    /// Creates a lab AKA vector with optional AUTS for resync tests.
    public init(rand: String, autn: String, res: String, ik: String, ck: String, auts: String? = nil) {
        self.rand = rand
        self.autn = autn
        self.res = res
        self.ik = ik
        self.ck = ck
        self.auts = auts
    }
}

/// Embedded lab SIM credentials and AKA vectors (replaces real UICC in tests).
public struct LabSimConfig: Codable, Sendable, Equatable {
    public var impi: String
    public var impus: [String]
    public var akaVectors: [AKAVector]

    enum CodingKeys: String, CodingKey {
        case impi
        case impus
        case akaVectors = "aka_vectors"
    }

    /// Creates lab SIM config with IMPI, IMPU list, and optional AKA vectors.
    public init(impi: String, impus: [String], akaVectors: [AKAVector] = []) {
        self.impi = impi
        self.impus = impus
        self.akaVectors = akaVectors
    }
}

/// Complete operator profile: everything the IMS client needs to register and call.
public struct OperatorProfile: Codable, Sendable, Equatable {
    public var profileID: String
    /// SIP home domain / IMS realm (e.g. ims.mnc001.mcc234.3gppnetwork.org).
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

    /// Creates a fully specified operator profile.
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

    /// Decodes from JSON, filling in defaults for optional sections.
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

    /// Encodes all profile fields to JSON.
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
