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

    public init(mode: PCSCFDiscoveryMode, address: String? = nil, port: Int? = nil) {
        self.mode = mode
        self.address = address
        self.port = port
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

    public init(mechanism: SecurityMechanism) {
        self.mechanism = mechanism
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
        self.labSim = labSim
    }
}
