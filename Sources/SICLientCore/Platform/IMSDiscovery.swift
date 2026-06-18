import Foundation

/// Minimal DNS SRV resolver for IMS P-CSCF discovery (RFC 2782 subset).
public enum IMSDNSResolver {
    public struct SRVRecord: Sendable, Equatable {
        public let target: String
        public let port: Int
        public let priority: Int
        public let weight: Int
    }

    public static func resolveSRV(service: String, domain: String, resolver: (String, UInt16, UInt16) throws -> [SRVRecord]) throws -> SRVRecord? {
        let name = "_\(service)._udp.\(domain)"
        let records = try resolver(name, 33, 1) // TYPE_SRV, CLASS_IN
        return records.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.weight > rhs.weight
        }.first
    }

    /// Parse raw DNS SRV RDATA payloads (used by tests and platform resolver).
    public static func parseSRVRecords(from answers: [(name: String, type: UInt16, rdata: Data)]) -> [SRVRecord] {
        answers.compactMap { answer in
            guard answer.type == 33, answer.rdata.count >= 7 else { return nil }
            let data = answer.rdata
            let priority = Int(UInt16(data[0]) << 8 | UInt16(data[1]))
            let weight = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
            let port = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
            let targetData = data.dropFirst(6)
            guard let target = decodeDNSName(targetData) else { return nil }
            return SRVRecord(target: target, port: port, priority: priority, weight: weight)
        }
    }

    private static func decodeDNSName(_ data: Data.SubSequence) -> String? {
        let bytes = Array(data)
        var labels: [String] = []
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            offset += 1
            if length == 0 { break }
            guard offset + length <= bytes.count else { return nil }
            let labelBytes = bytes[offset ..< offset + length]
            guard let label = String(bytes: labelBytes, encoding: .utf8) else { return nil }
            labels.append(label)
            offset += length
        }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}

public enum PCSCFDiscovery {
    public static func endpoint(from profile: OperatorProfile, resolver: any NetworkAdapter) throws -> PCSCFEndpoint {
        switch profile.pcscf.mode {
        case .static:
            guard
                let host = profile.pcscf.address,
                let port = profile.pcscf.port,
                let transport = profile.transport.preference.first
            else {
                throw NetworkAdapterError.discoveryUnavailable
            }
            return PCSCFEndpoint(host: host, port: port, transport: transport)
        case .pco:
            return try endpointFromAddressList(
                profile.pcscf.pcoAddresses ?? ProcessInfo.processInfo.environment["SICLIENT_PCO_PCSCF"].map { [$0] },
                profile: profile
            )
        case .dhcp:
            return try endpointFromAddressList(
                profile.pcscf.dhcpAddresses ?? ProcessInfo.processInfo.environment["SICLIENT_DHCP_PCSCF"].map { [$0] },
                profile: profile
            )
        }
    }

    public static func endpointFromDNS(profile: OperatorProfile, srvRecords: [IMSDNSResolver.SRVRecord]) throws -> PCSCFEndpoint {
        guard let record = srvRecords.sorted(by: { $0.priority < $1.priority }).first else {
            throw NetworkAdapterError.discoveryUnavailable
        }
        let transport = profile.transport.preference.first(where: { $0 == .udp || $0 == .tcp || $0 == .tls }) ?? .udp
        return PCSCFEndpoint(host: record.target, port: record.port, transport: transport)
    }

    private static func endpointFromAddressList(_ addresses: [String]?, profile: OperatorProfile) throws -> PCSCFEndpoint {
        guard let raw = addresses?.first else { throw NetworkAdapterError.discoveryUnavailable }
        let transport = profile.transport.preference.first ?? .udp
        if raw.contains(":") {
            let parts = raw.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let port = Int(parts[1]) else {
                throw NetworkAdapterError.discoveryUnavailable
            }
            return PCSCFEndpoint(host: String(parts[0]), port: port, transport: transport)
        }
        return PCSCFEndpoint(host: raw, port: profile.pcscf.port ?? 5060, transport: transport)
    }
}
