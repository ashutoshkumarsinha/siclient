import Foundation

// MARK: - File overview
//
// Bundles all platform adapters (SIM, network, bearer, access info) into one object.
// IMS (IP Multimedia Subsystem) registration and calls need credentials from the SIM,
// P-CSCF (Proxy Call Session Control Function) discovery from the network layer, and
// radio-access details for SIP headers.

/// Holds the four platform adapters the IMS stack needs at runtime.
public struct PlatformContext: Sendable {
    /// Reads IMS identity and AKA (Authentication and Key Agreement) credentials from the SIM.
    public let sim: any SimAdapter
    /// Discovers P-CSCF and provides local IP / DNS resolution.
    public let network: any NetworkAdapter
    /// Requests dedicated bearers for voice QoS (Quality of Service).
    public let bearer: any BearerAdapter
    /// Reports current radio access type and cell ID for PANI headers.
    public let accessInfo: any AccessInfoAdapter

    /// Wires together the four adapters supplied by the host platform.
    public init(
        sim: any SimAdapter,
        network: any NetworkAdapter,
        bearer: any BearerAdapter,
        accessInfo: any AccessInfoAdapter
    ) {
        self.sim = sim
        self.network = network
        self.bearer = bearer
        self.accessInfo = accessInfo
    }

    /// Builds a default test context with stub adapters chosen from the operator profile.
    public static func stubbed(profile: OperatorProfile) throws -> PlatformContext {
        return PlatformContext(
            sim: SimAdapterFactory.make(profile: profile),
            network: ProductionNetworkAdapter.forProfile(profile),
            bearer: StubBearerAdapter(),
            accessInfo: StubAccessInfoAdapter()
        )
    }
}
