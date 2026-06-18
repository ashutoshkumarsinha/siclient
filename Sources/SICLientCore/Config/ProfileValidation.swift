import Foundation

public enum ProfileValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyProfileID
    case emptyHomeDomain
    case staticPCSCFMissingAddress
    case staticPCSCFMissingPort
    case staticPCSCFInvalidPort(Int)
    case emptyTransportPreference
    case invalidRefreshRatio(Double)
    case invalidKeepalive(Int)
    case invalidPreconditionTimeout(Int)
    case invalidRTPPort(Int)
    case invalidMTUBytes(Int)
    case invalidRegistrationRetries(Int)
    case invalidNetworkRecoveryTimeout(Int)
    case labSimMissingIMPUs
    case labSimEmptyIMPI
    case invalidHexField(String, field: String)

    public var description: String {
        switch self {
        case .emptyProfileID:
            return "profile_id must not be empty"
        case .emptyHomeDomain:
            return "home_domain must not be empty"
        case .staticPCSCFMissingAddress:
            return "static P-CSCF mode requires address"
        case .staticPCSCFMissingPort:
            return "static P-CSCF mode requires port"
        case .staticPCSCFInvalidPort(let port):
            return "P-CSCF port out of range: \(port)"
        case .emptyTransportPreference:
            return "transport.preference must contain at least one protocol"
        case .invalidRefreshRatio(let ratio):
            return "registration_refresh_ratio must be between 0.1 and 0.95, got \(ratio)"
        case .invalidKeepalive(let seconds):
            return "keepalive_sec must be between 10 and 300, got \(seconds)"
        case .invalidPreconditionTimeout(let ms):
            return "fail_timeout_ms must be between 1000 and 60000, got \(ms)"
        case .invalidRTPPort(let port):
            return "media.local_rtp_port out of range: \(port)"
        case .invalidMTUBytes(let mtu):
            return "resilience.mtu_bytes out of range: \(mtu)"
        case .invalidRegistrationRetries(let retries):
            return "resilience.max_registration_retries out of range: \(retries)"
        case .invalidNetworkRecoveryTimeout(let seconds):
            return "resilience.network_recovery_timeout_sec out of range: \(seconds)"
        case .labSimMissingIMPUs:
            return "lab_sim.impus must contain at least one IMPU"
        case .labSimEmptyIMPI:
            return "lab_sim.impi must not be empty"
        case .invalidHexField(let value, let field):
            return "lab_sim.\(field) has invalid hex: \(value)"
        }
    }
}

public enum ProfileValidator {
  private static let hex16 = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{32}$")
  private static let hexVariable = try! NSRegularExpression(pattern: "^[0-9a-fA-F]+$")
  private static let hex14 = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{28}$")

    public static func validate(_ profile: OperatorProfile) throws {
        if profile.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileValidationError.emptyProfileID
        }

        if profile.homeDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileValidationError.emptyHomeDomain
        }

        if profile.pcscf.mode == .static {
            guard let address = profile.pcscf.address, !address.isEmpty else {
                throw ProfileValidationError.staticPCSCFMissingAddress
            }
            _ = address

            guard let port = profile.pcscf.port else {
                throw ProfileValidationError.staticPCSCFMissingPort
            }
            guard (1 ... 65535).contains(port) else {
                throw ProfileValidationError.staticPCSCFInvalidPort(port)
            }
        }

        if profile.transport.preference.isEmpty {
            throw ProfileValidationError.emptyTransportPreference
        }

        let ratio = profile.timers.registrationRefreshRatio
        guard (0.1 ... 0.95).contains(ratio) else {
            throw ProfileValidationError.invalidRefreshRatio(ratio)
        }

        let keepalive = profile.timers.keepaliveSec
        guard (10 ... 300).contains(keepalive) else {
            throw ProfileValidationError.invalidKeepalive(keepalive)
        }

        let timeout = profile.preconditions.failTimeoutMs
        guard (1000 ... 60000).contains(timeout) else {
            throw ProfileValidationError.invalidPreconditionTimeout(timeout)
        }

        let rtpPort = profile.media.localRTPPort
        guard (1024 ... 65535).contains(rtpPort) else {
            throw ProfileValidationError.invalidRTPPort(rtpPort)
        }

        let mtu = profile.resilience.mtuBytes
        guard (576 ... 9000).contains(mtu) else {
            throw ProfileValidationError.invalidMTUBytes(mtu)
        }

        let retries = profile.resilience.maxRegistrationRetries
        guard (1 ... 10).contains(retries) else {
            throw ProfileValidationError.invalidRegistrationRetries(retries)
        }

        let recovery = profile.resilience.networkRecoveryTimeoutSec
        guard (5 ... 120).contains(recovery) else {
            throw ProfileValidationError.invalidNetworkRecoveryTimeout(recovery)
        }

        if let labSim = profile.labSim {
            if labSim.impi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProfileValidationError.labSimEmptyIMPI
            }
            if labSim.impus.isEmpty {
                throw ProfileValidationError.labSimMissingIMPUs
            }

            for vector in labSim.akaVectors {
                try validateHex(vector.rand, field: "aka_vectors.rand", pattern: hex16)
                try validateHex(vector.autn, field: "aka_vectors.autn", pattern: hex16)
                try validateHex(vector.res, field: "aka_vectors.res", pattern: hexVariable)
                try validateHex(vector.ik, field: "aka_vectors.ik", pattern: hex16)
                try validateHex(vector.ck, field: "aka_vectors.ck", pattern: hex16)
                if let auts = vector.auts {
                    try validateHex(auts, field: "aka_vectors.auts", pattern: hex14)
                }
            }
        }
    }

    private static func validateHex(_ value: String, field: String, pattern: NSRegularExpression) throws {
        let range = NSRange(value.startIndex..., in: value)
        guard pattern.firstMatch(in: value, range: range) != nil else {
            throw ProfileValidationError.invalidHexField(value, field: field)
        }
    }
}
