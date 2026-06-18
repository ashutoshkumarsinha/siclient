import Foundation

public struct PlatformContext: Sendable {
    public let sim: any SimAdapter
    public let network: any NetworkAdapter
    public let bearer: any BearerAdapter
    public let accessInfo: any AccessInfoAdapter

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

    public static func stubbed(profile: OperatorProfile) throws -> PlatformContext {
        let sim: any SimAdapter
        if let labSim = profile.labSim {
            sim = LabSimAdapter(config: labSim)
        } else {
            sim = UnavailableSimAdapter()
        }

        return PlatformContext(
            sim: sim,
            network: StubNetworkAdapter(),
            bearer: StubBearerAdapter(),
            accessInfo: StubAccessInfoAdapter()
        )
    }
}

private struct UnavailableSimAdapter: SimAdapter {
    func getIMPI() throws -> String { throw SimAdapterError.noCredentials }
    func getIMPUList() throws -> [String] { throw SimAdapterError.noCredentials }
    func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        throw SimAdapterError.noCredentials
    }
}
