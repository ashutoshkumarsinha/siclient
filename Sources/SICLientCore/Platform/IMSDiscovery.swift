import Foundation

// MARK: - File overview
//
// This file helps the client find the P-CSCF (Proxy Call Session Control Function) — the
// first SIP (Session Initiation Protocol) server in an IMS (IP Multimedia Subsystem) network.
//
// It supports:
// - DNS SRV lookups (a DNS record type that points to a host and port)
// - Static addresses, PCO (Protocol Configuration Options from the cellular modem), and
//   DHCP (Dynamic Host Configuration Protocol) address lists

/// Minimal DNS (Domain Name System) SRV resolver for IMS P-CSCF discovery (RFC 2782 subset).
public enum IMSDNSResolver {
    /// One DNS SRV record: a target hostname, port, and priority/weight for ordering.
    public struct SRVRecord: Sendable, Equatable {
        public let target: String
        public let port: Int
        public let priority: Int
        public let weight: Int
    }

    /// Looks up the best SRV record for a SIP service in the given domain.
    /// Returns the record with the lowest priority; ties are broken by higher weight.
    public static func resolveSRV(service: String, domain: String, resolver: (String, UInt16, UInt16) throws -> [SRVRecord]) throws -> SRVRecord? {
        // Standard SRV name format: _service._protocol.domain (here: SIP over UDP)
        let name = "_\(service)._udp.\(domain)"
        let records = try resolver(name, 33, 1) // TYPE_SRV = 33, CLASS_IN = 1
        return records.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.weight > rhs.weight // Higher weight wins when priority is equal
        }.first
    }

    /// Parses raw DNS SRV answer payloads into structured records (used by tests and platform resolver).
    public static func parseSRVRecords(from answers: [(name: String, type: UInt16, rdata: Data)]) -> [SRVRecord] {
        answers.compactMap { answer in
            guard answer.type == 33, answer.rdata.count >= 7 else { return nil } // 33 = SRV type
            let data = answer.rdata
            // SRV RDATA layout: priority (2) + weight (2) + port (2) + target hostname
            let priority = Int(UInt16(data[0]) << 8 | UInt16(data[1]))
            let weight = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
            let port = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
            let targetData = data.dropFirst(6)
            guard let target = decodeDNSName(targetData) else { return nil }
            return SRVRecord(target: target, port: port, priority: priority, weight: weight)
        }
    }

    /// Decodes a DNS-encoded hostname (length-prefixed labels) into a dotted string.
    private static func decodeDNSName(_ data: Data.SubSequence) -> String? {
        let bytes = Array(data)
        var labels: [String] = []
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            offset += 1
            if length == 0 { break } // Zero-length label marks end of name
            guard offset + length <= bytes.count else { return nil }
            let labelBytes = bytes[offset ..< offset + length]
            guard let label = String(bytes: labelBytes, encoding: .utf8) else { return nil }
            labels.append(label)
            offset += length
        }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}

/// Resolves a P-CSCF endpoint from an operator profile using static, PCO, DHCP, or DNS SRV data.
public enum PCSCFDiscovery {
    /// Picks a P-CSCF host/port based on the profile's discovery mode.
    public static func endpoint(from profile: OperatorProfile, resolver: any NetworkAdapter) throws -> PCSCFEndpoint {
        switch profile.pcscf.mode {
        case .static:
            // Operator provided a fixed address and port in the profile
            guard
                let host = profile.pcscf.address,
                let port = profile.pcscf.port,
                let transport = profile.transport.preference.first
            else {
                throw NetworkAdapterError.discoveryUnavailable
            }
            return PCSCFEndpoint(host: host, port: port, transport: transport)
        case .pco:
            // Addresses pushed by the cellular modem during attach (or from a test env var)
            return try endpointFromAddressList(
                profile.pcscf.pcoAddresses ?? ProcessInfo.processInfo.environment["SICLIENT_PCO_PCSCF"].map { [$0] },
                profile: profile
            )
        case .dhcp:
            // Addresses from DHCP option 120 (or from a test env var)
            return try endpointFromAddressList(
                profile.pcscf.dhcpAddresses ?? ProcessInfo.processInfo.environment["SICLIENT_DHCP_PCSCF"].map { [$0] },
                profile: profile
            )
        }
    }

    /// Builds a P-CSCF endpoint from pre-fetched DNS SRV records.
    public static func endpointFromDNS(profile: OperatorProfile, srvRecords: [IMSDNSResolver.SRVRecord]) throws -> PCSCFEndpoint {
        guard let record = srvRecords.sorted(by: { $0.priority < $1.priority }).first else {
            throw NetworkAdapterError.discoveryUnavailable
        }
        let transport = profile.transport.preference.first(where: { $0 == .udp || $0 == .tcp || $0 == .tls }) ?? .udp
        return PCSCFEndpoint(host: record.target, port: record.port, transport: transport)
    }

    /// Parses "host:port" or bare hostname strings from PCO/DHCP address lists.
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
        // No port in the string — fall back to profile port or SIP default 5060
        return PCSCFEndpoint(host: raw, port: profile.pcscf.port ?? 5060, transport: transport)
    }
}
